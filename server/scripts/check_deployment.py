"""Verify a deployed private gateway; --live makes four billable model calls.

Run from the repository root with:
uv run --directory server python scripts/check_deployment.py https://YOUR-HOST --live
The private client token is read from the environment or a hidden terminal prompt.
"""

import argparse
import getpass
import os
import sys
from urllib.parse import urlsplit
from uuid import uuid4

import httpx

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from app.schemas import Feedback, Reply  # noqa: E402


def endpoint(value: str) -> str:
    url = urlsplit(value)
    if (
        url.scheme != "https"
        or not url.hostname
        or url.username
        or url.password
        or url.query
        or url.fragment
        or url.path not in ("", "/")
    ):
        raise argparse.ArgumentTypeError("Use the HTTPS service origin without credentials or a path")
    return value.rstrip("/")


def body(language: str, messages: list[dict[str, str]]) -> dict:
    return {
        "requestID": str(uuid4()),
        "language": language,
        "level": "beginner",
        "scene": "daily",
        "messages": messages,
    }


def require_status(response: httpx.Response, expected: int, operation: str) -> None:
    if response.status_code != expected:
        # Do not print arbitrary upstream error bodies, headers, or credentials.
        raise RuntimeError(f"{operation}: expected HTTP {expected}, received {response.status_code}")


def check(base_url: str, *, live: bool) -> None:
    with httpx.Client(base_url=base_url, timeout=120, follow_redirects=False) as client:
        health = client.get("/health")
        require_status(health, 200, "health")
        state = health.json()
        if state.get("status") != "ok" or state.get("aiConfigured") is not True:
            raise RuntimeError("Service is running but model key/private token/expiry are not ready")
        print("HTTPS health: ready (does not by itself verify the model)", flush=True)

        messages = [{"role": "user", "content": "I am agree with my friend."}]
        unauthenticated = client.post("/v1/tutor/reply", json=body("en", messages))
        require_status(unauthenticated, 401, "unauthenticated request")
        print("Unauthenticated model requests: rejected", flush=True)
        if not live:
            return

        token = os.getenv("LINGUAMATE_CLIENT_TOKEN", "")
        if not token and sys.stdin.isatty():
            token = getpass.getpass("Private backend token (not the DeepSeek key): ")
        if len(token) < 32:
            raise RuntimeError("Set LINGUAMATE_CLIENT_TOKEN or enter it at the hidden prompt")
        headers = {"Authorization": "Bearer " + token}
        for language, text in [("en", "I am agree with my friend."), ("ko", "저는 친구을 만나요.")]:
            messages = [{"role": "user", "content": text}]
            response = client.post("/v1/tutor/reply", json=body(language, messages), headers=headers)
            require_status(response, 200, language + " reply")
            reply = Reply.model_validate(response.json())
            messages.append({"role": "assistant", "content": reply.reply})
            response = client.post("/v1/tutor/feedback", json=body(language, messages), headers=headers)
            require_status(response, 200, language + " feedback")
            feedback = Feedback.model_validate(response.json())
            if not feedback.summary.strip() or not feedback.followUp.strip():
                raise RuntimeError(language + " feedback is empty")
            if any(item.original not in text for item in feedback.corrections):
                raise RuntimeError(language + " feedback quotes text the learner did not write")
            print(language + ": live reply and structured feedback passed", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url", type=endpoint)
    parser.add_argument(
        "--live", action="store_true", help="Make four billable model calls using synthetic text"
    )
    args = parser.parse_args()
    try:
        check(args.url, live=args.live)
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        return 1
    except (httpx.HTTPError, ValueError):
        print("Connection, TLS, or response validation failed; no secrets were logged", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
