from urllib.parse import urlparse

import httpx
from pydantic import ValidationError

from .prompts import system_prompt
from .schemas import Feedback, Reply, TutorRequest
from .settings import Settings


class ProviderFailure(Exception):
    """Safe error: never include provider response bodies or credentials."""


class ModelProvider:
    def __init__(self, settings: Settings, transport: httpx.AsyncBaseTransport | None = None):
        self.settings = settings
        self.transport = transport

    async def generate(self, request: TutorRequest, *, feedback: bool) -> Reply | Feedback:
        messages = [
            {"role": "system", "content": system_prompt(request, feedback)},
            *[message.model_dump() for message in request.messages],
        ]
        if feedback:
            # A completed conversation ends with the tutor's message. Ask for a
            # fresh user turn instead of relying on assistant-prefix continuation,
            # which has different semantics in DeepSeek-compatible APIs.
            messages.append(
                {
                    "role": "user",
                    "content": "请结束本次练习，按系统要求输出 JSON 反馈。纠错只引用前面的学习者原话。",
                }
            )
        body = {
            "model": self.settings.llm_model,
            "messages": messages,
            "response_format": {"type": "json_object"},
            "max_tokens": 2200 if feedback else 600,
        }
        if urlparse(self.settings.llm_base_url).hostname == "api.deepseek.com":
            # Current DeepSeek models enable thinking by default. Short tutoring
            # responses use non-thinking mode so the output budget is for visible
            # text/JSON and the existing interactive timeout remains appropriate.
            body["thinking"] = {"type": "disabled"}
        try:
            async with httpx.AsyncClient(
                timeout=30, transport=self.transport, follow_redirects=False
            ) as client:
                response = await client.post(
                    self.settings.llm_base_url + "/chat/completions",
                    headers={"Authorization": "Bearer " + self.settings.llm_api_key.get_secret_value()},
                    json=body,
                )
                response.raise_for_status()
                choice = response.json()["choices"][0]
                if choice.get("finish_reason") not in (None, "stop"):
                    raise ProviderFailure("Model output did not complete normally")
                content = choice["message"]["content"]
                result = (Feedback if feedback else Reply).model_validate_json(content)
                if isinstance(result, Feedback):
                    learner_messages = [m.content for m in request.messages if m.role == "user"]
                    if any(
                        not any(c.original in text for text in learner_messages) for c in result.corrections
                    ):
                        raise ProviderFailure("Feedback quoted text that the learner did not write")
                return result
        except (httpx.HTTPError, ValueError, KeyError, IndexError, TypeError, ValidationError) as exc:
            raise ProviderFailure("Model request or response validation failed") from exc
