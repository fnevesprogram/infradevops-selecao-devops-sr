"""Probes de liveness, readiness e health legado."""

from __future__ import annotations

from fastapi import FastAPI, HTTPException, status

from app.src.config import settings
from app.src.database import check_db_health
from app.src.schemas import HealthResponse, LivenessResponse


def _unavailable(status_label: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail={
            "status": status_label,
            "database": "disconnected",
            "version": settings.app_version,
        },
    )


def register_health_routes(app: FastAPI) -> None:
    """Registra probes diretamente no app (compatível com Prometheus instrumentator)."""

    @app.get(
        "/health/live",
        response_model=LivenessResponse,
        tags=["Observability"],
        summary="Liveness probe (processo da API ativo)",
    )
    async def liveness_check() -> LivenessResponse:
        return LivenessResponse(version=settings.app_version)

    @app.get(
        "/health/ready",
        response_model=HealthResponse,
        tags=["Observability"],
        summary="Readiness probe (banco disponível)",
    )
    async def readiness_check() -> HealthResponse:
        if not await check_db_health():
            raise _unavailable("not_ready")
        return HealthResponse(
            status="ready",
            database="connected",
            version=settings.app_version,
        )

    @app.get(
        "/health",
        response_model=HealthResponse,
        tags=["Observability"],
        summary="Health check legado (inclui banco)",
    )
    async def health_check() -> HealthResponse:
        if not await check_db_health():
            raise _unavailable("unhealthy")
        return HealthResponse(
            status="healthy",
            database="connected",
            version=settings.app_version,
        )
