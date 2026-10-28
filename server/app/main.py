import asyncio
import hashlib
import hmac
import time
from collections import OrderedDict, deque
from datetime import UTC, datetime, timedelta

from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import JSONResponse

from .provider import ModelProvider, ProviderFailure
from .schemas import Feedback, Reply, TutorRequest
from .settings import Settings


def create_app(settings: Settings | None = None, provider: ModelProvider | None = None) -> FastAPI:
    settings = settings or Settings()
    service = provider or ModelProvider(settings)
    app = FastAPI(title="LinguaMate private tutor", version="0.1.0", docs_url=None, redoc_url=None)
    app.state.provider = service
    lock = asyncio.Lock()
    cache: OrderedDict[str, tuple[float, str, Reply | Feedback]] = OrderedDict()
    recent: deque[float] = deque()
    daily = {"day": datetime.now(UTC).date(), "count": 0}

    def auth_ready() -> bool:
        expiry = settings.linguamate_token_expires_at
        now = datetime.now(UTC)
        return bool(
            len(settings.linguamate_client_token.get_secret_value()) >= 32
            and expiry
            and now < expiry <= now + timedelta(days=7)
        )

    @app.middleware("http")
    async def bounded_body(request: Request, call_next):
        # Bound streaming bodies too; Content-Length alone is insufficient.
        if request.method == "POST":
            body = bytearray()
            async for chunk in request.stream():
                body.extend(chunk)
                if len(body) > 131072:
                    return JSONResponse({"detail": "Request body too large"}, status_code=413)
            request._body = bytes(body)
        response = await call_next(request)
        response.headers["Cache-Control"] = "no-store"
        return response

    @app.get("/health")
    async def health():
        return {
            "status": "ok",
            "aiConfigured": settings.model_ready and auth_ready(),
            "mode": "private-pilot",
        }

    async def execute(payload: TutorRequest, authorization: str | None, feedback: bool):
        if not auth_ready():
            raise HTTPException(503, "Private access token and expiry must be configured")
        expected = "Bearer " + settings.linguamate_client_token.get_secret_value()
        if authorization is None or not hmac.compare_digest(authorization.encode(), expected.encode()):
            raise HTTPException(401, "Invalid or expired access token")
        if not settings.model_ready:
            raise HTTPException(503, "Model provider is not configured")
        expected_last_role = "assistant" if feedback else "user"
        if payload.messages[-1].role != expected_last_role:
            raise HTTPException(422, "Conversation is not ready for this operation")
        key = ("feedback:" if feedback else "reply:") + str(payload.requestID)
        digest = hashlib.sha256(payload.model_dump_json().encode()).hexdigest()
        try:
            await asyncio.wait_for(lock.acquire(), timeout=3)
        except TimeoutError as exc:
            raise HTTPException(429, "Another request is in progress; retry shortly") from exc
        try:
            now = time.monotonic()
            while cache and next(iter(cache.values()))[0] < now - 600:
                cache.popitem(last=False)
            if key in cache:
                _, previous_digest, result = cache[key]
                if digest != previous_digest:
                    raise HTTPException(409, "Request ID reused with different content")
                return result
            while recent and recent[0] < now - 60:
                recent.popleft()
            today = datetime.now(UTC).date()
            if daily["day"] != today:
                daily.update(day=today, count=0)
            if len(recent) >= 20 or daily["count"] >= settings.linguamate_daily_limit:
                raise HTTPException(429, "Private pilot request quota exceeded")
            recent.append(now)
            daily["count"] += 1  # Failed provider calls also consume budget.
            try:
                result = await asyncio.wait_for(service.generate(payload, feedback=feedback), timeout=35)
            except (ProviderFailure, TimeoutError) as exc:
                raise HTTPException(502, "AI service could not complete this request; please retry") from exc
            cache[key] = (time.monotonic(), digest, result)
            while len(cache) > 128:
                cache.popitem(last=False)
            return result
        finally:
            lock.release()

    @app.post("/v1/tutor/reply", response_model=Reply)
    async def reply(payload: TutorRequest, authorization: str | None = Header(default=None)):
        return await execute(payload, authorization, False)

    @app.post("/v1/tutor/feedback", response_model=Feedback)
    async def feedback(payload: TutorRequest, authorization: str | None = Header(default=None)):
        return await execute(payload, authorization, True)

    return app


app = create_app()
