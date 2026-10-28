import asyncio
import json
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import httpx
import pytest

from app.main import create_app
from app.provider import ModelProvider, ProviderFailure
from app.schemas import Feedback, Reply, TutorRequest
from app.settings import Settings

TOKEN = "test-only-private-token-not-for-deployment-12345"


def settings(**overrides):
    return Settings(
        _env_file=None,
        **(
            {
                "llm_base_url": "https://api.openai.com/v1",
                "llm_api_key": "test-provider-key",
                "llm_model": "test-model",
                "linguamate_client_token": TOKEN,
                "linguamate_token_expires_at": datetime.now(UTC) + timedelta(hours=1),
            }
            | overrides
        ),
    )


def payload(language="en", feedback=False):
    messages = [{"role": "user", "content": "I am agree" if language == "en" else "친구을 만나요"}]
    if feedback:
        messages.append({"role": "assistant", "content": "Could you give an example?"})
    return {
        "requestID": str(uuid4()),
        "language": language,
        "level": "beginner",
        "scene": "daily",
        "messages": messages,
    }


class FakeProvider:
    def __init__(self):
        self.calls = 0

    async def generate(self, request, *, feedback):
        self.calls += 1
        if feedback:
            return Feedback(
                summary="测试反馈，不是真实 AI", corrections=[], suggestions=[], followUp="再写一个例句"
            )
        return Reply(reply="What do you think?" if request.language == "en" else "어떻게 생각하세요?")


def client(app, token=TOKEN):
    return httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://test",
        headers={"Authorization": "Bearer " + token},
    )


async def test_health_does_not_claim_ai_without_configuration():
    async with client(create_app(Settings(_env_file=None))) as c:
        response = await c.get("/health")
        assert response.status_code == 200
        assert response.json()["aiConfigured"] is False
        response = await c.post("/v1/tutor/reply", json=payload())
        assert response.status_code == 503


@pytest.mark.parametrize("language", ["en", "ko"])
async def test_conversation_and_feedback(language):
    async with client(create_app(settings(), FakeProvider())) as c:
        response = await c.post("/v1/tutor/reply", json=payload(language))
        assert response.status_code == 200
        assert response.json()["reply"]
        response = await c.post("/v1/tutor/feedback", json=payload(language, True))
        assert response.status_code == 200
        assert set(response.json()) == {"summary", "corrections", "suggestions", "followUp"}
        assert response.headers["cache-control"] == "no-store"


async def test_wrong_token_never_calls_model():
    provider = FakeProvider()
    async with client(create_app(settings(), provider), "wrong") as c:
        response = await c.post("/v1/tutor/reply", json=payload())
        assert response.status_code == 401
        assert provider.calls == 0


async def test_expired_and_overlong_token_validity_are_rejected():
    for expiry in [datetime.now(UTC) - timedelta(seconds=1), datetime.now(UTC) + timedelta(days=8)]:
        async with client(create_app(settings(linguamate_token_expires_at=expiry), FakeProvider())) as c:
            assert (await c.post("/v1/tutor/reply", json=payload())).status_code == 503


async def test_missing_model_key_fails_explicitly():
    async with client(create_app(settings(llm_api_key=""), FakeProvider())) as c:
        assert (await c.post("/v1/tutor/reply", json=payload())).status_code == 503


async def test_retry_is_idempotent_and_conflicts_are_rejected():
    provider = FakeProvider()
    app = create_app(settings(), provider)
    body = payload()
    async with client(app) as c:
        first, second = await asyncio.gather(
            c.post("/v1/tutor/reply", json=body), c.post("/v1/tutor/reply", json=body)
        )
        assert first.status_code == second.status_code == 200
        assert first.json() == second.json()
        assert provider.calls == 1
        body["messages"][0]["content"] = "Different content"
        assert (await c.post("/v1/tutor/reply", json=body)).status_code == 409
        assert provider.calls == 1


async def test_daily_quota_applies_but_does_not_charge_cached_retry():
    provider = FakeProvider()
    async with client(create_app(settings(linguamate_daily_limit=1), provider)) as c:
        body = payload()
        assert (await c.post("/v1/tutor/reply", json=body)).status_code == 200
        assert (await c.post("/v1/tutor/reply", json=body)).status_code == 200
        assert (await c.post("/v1/tutor/reply", json=payload())).status_code == 429
        assert provider.calls == 1


async def test_oversize_invalid_and_wrong_phase_requests():
    provider = FakeProvider()
    async with client(create_app(settings(), provider)) as c:
        assert (await c.post("/v1/tutor/reply", content=b"a" * 131073)).status_code == 413
        body = payload()
        body["messages"][0]["content"] = "a" * 3001
        assert (await c.post("/v1/tutor/reply", json=body)).status_code == 422
        body = payload()
        body["messages"][0]["role"] = "system"
        assert (await c.post("/v1/tutor/reply", json=body)).status_code == 422
        assert (await c.post("/v1/tutor/feedback", json=payload())).status_code == 422
        assert (await c.post("/v1/tutor/reply", json=payload(feedback=True))).status_code == 422
        assert provider.calls == 0


async def test_failure_does_not_leak_provider_secrets_or_poison_retry():
    class FailingProvider(FakeProvider):
        async def generate(self, request, *, feedback):
            self.calls += 1
            if self.calls == 1:
                raise ProviderFailure("private upstream detail and test-provider-key")
            return Reply(reply="Recovered")

    async with client(create_app(settings(), FailingProvider())) as c:
        body = payload()
        response = await c.post("/v1/tutor/reply", json=body)
        assert response.status_code == 502
        assert "test-provider-key" not in response.text
        assert "private upstream detail" not in response.text
        assert (await c.post("/v1/tutor/reply", json=body)).status_code == 200


async def test_real_provider_adapter_request_and_reply_contract():
    def respond(request: httpx.Request):
        assert request.url == "https://api.openai.com/v1/chat/completions"
        assert request.headers["authorization"] == "Bearer test-provider-key"
        body = json.loads(request.content)
        assert body["messages"][0]["role"] == "system"
        assert body["messages"][-1]["content"] == "친구을 만나요"
        assert body["response_format"] == {"type": "json_object"}
        assert "thinking" not in body
        return httpx.Response(
            200, json={"choices": [{"message": {"content": '{"reply":"친구와 무엇을 하세요?"}'}}]}
        )

    provider = ModelProvider(settings(), httpx.MockTransport(respond))
    result = await provider.generate(TutorRequest.model_validate(payload("ko")), feedback=False)
    assert result.reply == "친구와 무엇을 하세요?"


@pytest.mark.parametrize(
    "content", ["", "not json", '{"reply":""}', '{"reply":"ok","score":9}', '{"summary":"wrong shape"}']
)
async def test_model_response_is_validated(content):
    transport = httpx.MockTransport(
        lambda request: httpx.Response(200, json={"choices": [{"message": {"content": content}}]})
    )
    with pytest.raises(ProviderFailure):
        await ModelProvider(settings(), transport).generate(
            TutorRequest.model_validate(payload()), feedback=False
        )


async def test_feedback_rejects_fabricated_quotes_and_pronunciation_scores():
    data = {
        "summary": "建议",
        "corrections": [
            {
                "kind": "grammar",
                "original": "not in the conversation",
                "improved": "improvement",
                "explanation": "说明",
            }
        ],
        "suggestions": [],
        "followUp": "练习",
    }

    def respond(request):
        return httpx.Response(200, json={"choices": [{"message": {"content": json.dumps(data)}}]})

    provider = ModelProvider(settings(), httpx.MockTransport(respond))
    with pytest.raises(ProviderFailure):
        await provider.generate(TutorRequest.model_validate(payload(feedback=True)), feedback=True)
    data["corrections"][0]["original"] = "I am agree"
    data["corrections"][0]["kind"] = "pronunciation"
    with pytest.raises(ProviderFailure):
        await provider.generate(TutorRequest.model_validate(payload(feedback=True)), feedback=True)
    data["corrections"][0]["kind"] = "grammar"
    result = await provider.generate(TutorRequest.model_validate(payload(feedback=True)), feedback=True)
    assert result.corrections[0].original == "I am agree"


def test_insecure_or_embedded_credential_provider_urls_rejected():
    for address in [
        "http://example.com/v1",
        "https://user:secret@example.com",
        "https://example.com?key=secret",
    ]:
        with pytest.raises(ValueError):
            settings(llm_base_url=address)


def test_deepseek_defaults_do_not_imply_credentials(monkeypatch):
    for name in ["LLM_BASE_URL", "LLM_MODEL", "LLM_API_KEY"]:
        monkeypatch.delenv(name, raising=False)
    configured = Settings(_env_file=None)
    assert configured.llm_base_url == "https://api.deepseek.com/v1"
    assert configured.llm_model == "deepseek-flash"
    assert not configured.model_ready


@pytest.mark.parametrize("language", ["en", "ko"])
@pytest.mark.parametrize("feedback", [False, True])
async def test_deepseek_reply_and_feedback_transport(language, feedback):
    body = payload(language, feedback)
    original = body["messages"][0]["content"]
    expected = (
        {
            "summary": "测试反馈，不是真实模型评价",
            "corrections": [
                {
                    "kind": "grammar",
                    "original": original,
                    "improved": "I agree" if language == "en" else "친구를 만나요",
                    "explanation": "测试用说明",
                }
            ],
            "suggestions": [],
            "followUp": "请再写一个例句",
        }
        if feedback
        else {"reply": "What do you think?" if language == "en" else "어떻게 생각하세요?"}
    )

    def respond(request: httpx.Request):
        assert request.url == "https://api.deepseek.com/v1/chat/completions"
        assert request.headers["authorization"] == "Bearer test-provider-key"
        sent = json.loads(request.content)
        assert sent["model"] == "deepseek-flash"
        assert sent["response_format"] == {"type": "json_object"}
        assert sent["thinking"] == {"type": "disabled"}
        assert "json" in sent["messages"][0]["content"].lower()
        assert sent["messages"][-1]["role"] == "user"
        if feedback:
            assert sent["messages"][1:-1] == body["messages"]
            assert "纠错只引用" in sent["messages"][-1]["content"]
        else:
            assert sent["messages"][1:] == body["messages"]
        return httpx.Response(
            200,
            json={
                "choices": [
                    {
                        "finish_reason": "stop",
                        "message": {
                            "role": "assistant",
                            "content": json.dumps(expected),
                            "reasoning_content": None,
                        },
                    }
                ]
            },
        )

    configured = settings(llm_base_url="https://api.deepseek.com/v1/", llm_model="deepseek-flash")
    provider = ModelProvider(configured, httpx.MockTransport(respond))
    result = await provider.generate(TutorRequest.model_validate(body), feedback=feedback)
    assert result.model_dump() == expected


@pytest.mark.parametrize("finish_reason", ["length", "content_filter"])
async def test_incomplete_model_completion_is_rejected_even_with_valid_json(finish_reason):
    transport = httpx.MockTransport(
        lambda request: httpx.Response(
            200,
            json={
                "choices": [
                    {
                        "finish_reason": finish_reason,
                        "message": {"content": '{"reply":"partial answer"}'},
                    }
                ]
            },
        )
    )
    provider = ModelProvider(settings(llm_base_url="https://api.deepseek.com/v1"), transport)
    with pytest.raises(ProviderFailure):
        await provider.generate(TutorRequest.model_validate(payload()), feedback=False)
