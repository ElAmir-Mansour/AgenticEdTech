import os
from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field

class Settings(BaseSettings):
    GOOGLE_API_KEY: str = Field(default="mock_key")
    GROQ_API_KEY: str = Field(default="mock_key")
    DATABASE_URL: str = Field(default="sqlite+aiosqlite:///./edtech.db")
    QDRANT_URL: str = Field(default="")
    QDRANT_API_KEY: str = Field(default="")
    JWT_SECRET: str = Field(default="local_development_jwt_secret_token_1234567890")
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 1440
    ENV: str = "development"
    HOST: str = "0.0.0.0"
    PORT: int = 8080

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore"
    )

settings = Settings()
