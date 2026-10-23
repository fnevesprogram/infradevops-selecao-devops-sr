"""Configuração tipada via variáveis de ambiente (12-factor)."""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Parâmetros de runtime da Comments API."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    app_name: str = "Comments API"
    app_version: str = "1.0.0"
    debug: bool = False
    host: str = "0.0.0.0"
    port: int = 8000
    database_url: str = "sqlite+aiosqlite:///:memory:"
    log_level: str = "INFO"

    @property
    def log_level_name(self) -> str:
        return self.log_level.upper()


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Retorna Settings em cache (singleton leve)."""
    return Settings()


settings = get_settings()
