"""Application factory da Comments API (FastAPI)."""

from __future__ import annotations

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from prometheus_fastapi_instrumentator import Instrumentator

from app.src.config import settings
from app.src.database import init_db
from app.src.routers import register_comments_routes, register_health_routes

logging.basicConfig(
    level=getattr(logging, settings.log_level_name, logging.INFO),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("comments_api")


@asynccontextmanager
async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
    logger.info(
        "Starting up %s v%s (database_ssl=%s)",
        settings.app_name,
        settings.app_version,
        settings.database_ssl,
    )
    try:
        await init_db()
    except Exception:
        logger.exception("Failed to initialize database on startup")
    yield
    logger.info("Shutting down %s", settings.app_name)


def create_app() -> FastAPI:
    """Monta a aplicação com rotas, lifespan e métricas Prometheus."""
    application = FastAPI(
        title=settings.app_name,
        version=settings.app_version,
        description=(
            "API REST de Comentários desenvolvida para o "
            "Desafio Técnico de Analista DevOps Sênior."
        ),
        docs_url="/docs",
        redoc_url="/redoc",
        lifespan=lifespan,
    )

    # Rotas registradas no app (evita _IncludedRouter incompatível com o instrumentator)
    register_health_routes(application)
    register_comments_routes(application)

    (
        Instrumentator(
            should_group_status_codes=False,
            should_ignore_untemplated=True,
            should_respect_env_var=False,
            excluded_handlers=["/metrics", "/health", "/health/live", "/health/ready"],
            env_var_name="ENABLE_METRICS",
        )
        .instrument(application)
        .expose(application, endpoint="/metrics", include_in_schema=True)
    )

    return application


app = create_app()
