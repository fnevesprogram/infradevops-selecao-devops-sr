"""Engine async, sessões e healthcheck do banco."""

from __future__ import annotations

import logging
from collections.abc import AsyncGenerator
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.src.config import settings
from app.src.models import Base

logger = logging.getLogger(__name__)

_POSTGRES_PREFIXES = ("postgres://", "postgresql://")
_ASYNCPG_PREFIX = "postgresql+asyncpg://"


def normalize_database_url(url: str) -> str:
    """Garante dialeto asyncpg para URLs Postgres."""
    if url.startswith(_ASYNCPG_PREFIX) or url.startswith("sqlite"):
        return url
    if url.startswith("postgres://"):
        return url.replace("postgres://", _ASYNCPG_PREFIX, 1)
    if url.startswith("postgresql://"):
        return url.replace("postgresql://", _ASYNCPG_PREFIX, 1)
    return url


def _engine_kwargs(database_url: str, *, debug: bool) -> dict[str, Any]:
    kwargs: dict[str, Any] = {"echo": debug, "pool_pre_ping": True}
    if not database_url.startswith("sqlite"):
        kwargs.update(pool_size=10, max_overflow=20, pool_recycle=1800)
    return kwargs


def build_engine(
    database_url: str | None = None,
    *,
    debug: bool | None = None,
) -> AsyncEngine:
    """Factory do AsyncEngine."""
    url = normalize_database_url(database_url or settings.database_url)
    return create_async_engine(
        url,
        **_engine_kwargs(url, debug=settings.debug if debug is None else debug),
    )


engine = build_engine()
async_session_maker = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


async def init_db() -> None:
    """Cria tabelas se ainda não existirem."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    logger.info("Database tables verified/created successfully.")


async def check_db_health() -> bool:
    """Ping leve (`SELECT 1`) para readiness."""
    try:
        async with engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
        return True
    except Exception:
        logger.exception("Database health check failed")
        return False


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """Dependency FastAPI: sessão async com rollback em erro."""
    async with async_session_maker() as session:
        try:
            yield session
        except Exception:
            await session.rollback()
            raise
