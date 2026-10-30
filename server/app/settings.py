from urllib.parse import urlparse

from pydantic import SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")
    llm_base_url: str = "https://api.deepseek.com/v1"
    llm_model: str = "deepseek-flash"
    llm_api_key: SecretStr = SecretStr("")
    linguamate_client_token: SecretStr = SecretStr("")
    linguamate_daily_limit: int = 200

    @field_validator("llm_base_url")
    @classmethod
    def secure_endpoint(cls, value: str) -> str:
        url = urlparse(value)
        if (
            url.scheme != "https"
            or not url.hostname
            or url.username
            or url.password
            or url.query
            or url.fragment
        ):
            raise ValueError("LLM_BASE_URL must be an HTTPS URL without credentials, query or fragment")
        return value.rstrip("/")

    @field_validator("linguamate_daily_limit")
    @classmethod
    def bounded_limit(cls, value: int) -> int:
        if not 1 <= value <= 1000:
            raise ValueError("Daily request limit must be between 1 and 1000")
        return value

    @property
    def model_ready(self) -> bool:
        return bool(self.llm_model.strip() and self.llm_api_key.get_secret_value())
