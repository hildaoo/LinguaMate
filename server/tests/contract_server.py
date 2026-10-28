"""Loopback-only transport fixture; never use this as an AI server or deploy it."""

import uvicorn

from app.main import create_app
from tests.test_api import FakeProvider, settings

if __name__ == "__main__":
    uvicorn.run(create_app(settings(), FakeProvider()), host="127.0.0.1", port=8765, log_level="warning")
