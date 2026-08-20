"""
Fin-Guard Analytics – Agent Configuration
==========================================
Loads all settings from environment variables (.env file).
Single source of truth for thresholds, DB, Slack, and OpenAI settings.
"""

from __future__ import annotations

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # ─── Pydantic v2 config (replaces the deprecated inner class Config) ───────
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        populate_by_name=True,
        extra="ignore",           # silently ignore unknown env vars
    )

    # ─── Database ─────────────────────────────────────────────────────────────
    db_host:     str = "localhost"
    db_port:     int = 5432
    db_name:     str = "fingard_db"
    db_user:     str = "fingard"
    db_password: str = "fingard_secret"

    @property
    def db_url(self) -> str:
        return (
            f"postgresql+psycopg2://{self.db_user}:{self.db_password}"
            f"@{self.db_host}:{self.db_port}/{self.db_name}"
        )

    # ─── OpenAI ───────────────────────────────────────────────────────────────
    openai_api_key: str = Field(default="", alias="OPENAI_API_KEY")
    openai_model:   str = "gpt-4o"

    # ─── Slack ────────────────────────────────────────────────────────────────
    slack_webhook_url: str = Field(default="", alias="SLACK_WEBHOOK_URL")
    slack_channel:     str = "#fin-guard-alerts"

    # ─── Agent polling ────────────────────────────────────────────────────────
    poll_interval_seconds: int = 300   # 5 minutes

    # ─── KPI Thresholds ───────────────────────────────────────────────────────
    par30_threshold:         float = 5.0    # %
    default_rate_threshold:  float = 3.0    # %
    anomaly_count_threshold: int   = 50
    npl_ratio_threshold:     float = 8.0    # %


# Singleton – import this everywhere
settings = Settings()
