"""Check the real container entrypoint with temporary, non-production configuration."""

import json
import os
import secrets
import subprocess
import sys
import time
from datetime import UTC, datetime, timedelta
from urllib.error import HTTPError, URLError
from urllib.request import ProxyHandler, Request, build_opener
from uuid import uuid4


def docker(*arguments, env=None):
    return subprocess.check_output(["docker", *arguments], text=True, env=env).strip()


def check(image, configured):
    environment = dict(os.environ)
    environment.update(
        PORT="10000",  # Exercise the port supplied by a hosting platform.
        LLM_API_KEY="container-test-only-not-a-real-key" if configured else "",
        LINGUAMATE_CLIENT_TOKEN=secrets.token_urlsafe(32) if configured else "",
        LINGUAMATE_TOKEN_EXPIRES_AT=(datetime.now(UTC) + timedelta(hours=1)).isoformat(),
    )
    arguments = ["run", "--rm", "--detach", "--publish", "127.0.0.1::10000"]
    for name in ["PORT", "LLM_API_KEY", "LINGUAMATE_CLIENT_TOKEN", "LINGUAMATE_TOKEN_EXPIRES_AT"]:
        arguments.extend(["--env", name])
    container = docker(*arguments, image, env=environment)
    try:
        address = docker("port", container, "10000/tcp")
        opener = build_opener(ProxyHandler({}))  # Local container traffic only.
        origin = "http://" + address
        for attempt in range(40):
            try:
                with opener.open(origin + "/health", timeout=2) as response:
                    health = json.load(response)
                break
            except (URLError, TimeoutError, ConnectionError):
                if attempt == 39:
                    raise RuntimeError("Container did not become healthy") from None
                time.sleep(0.25)
        if health.get("status") != "ok" or health.get("aiConfigured") is not configured:
            raise RuntimeError("Unexpected container health state")
        payload = {
            "requestID": str(uuid4()), "language": "en", "level": "beginner", "scene": "daily",
            "messages": [{"role": "user", "content": "Hello"}],
        }
        request = Request(
            origin + "/v1/tutor/reply", data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"}, method="POST",
        )
        try:
            with opener.open(request, timeout=3):
                raise RuntimeError("Unauthenticated request was accepted")
        except HTTPError as error:
            expected = 401 if configured else 503
            if error.code != expected:
                raise RuntimeError(f"Expected HTTP {expected}, received {error.code}") from None
        docker(
            "exec", container, "python", "-c",
            "import os,pathlib; assert os.geteuid()==10001; "
            "assert not pathlib.Path('/app/.env').exists(); "
            "assert not pathlib.Path('/app/tests').exists()",
        )
        print(f"Container configured={configured}: PORT, health, auth, non-root and file isolation passed")
    finally:
        subprocess.run(["docker", "rm", "--force", container], check=False, stdout=subprocess.DEVNULL)


if __name__ == "__main__":
    image = sys.argv[1] if len(sys.argv) == 2 else "linguamate-api:deployment-check"
    check(image, False)
    check(image, True)
