"""Schemas Pydantic (request/response)."""

from __future__ import annotations

from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field

NonEmptyComment = Annotated[
    str,
    Field(min_length=1, max_length=2000, description="Texto do comentário"),
]
PositiveContentId = Annotated[
    int,
    Field(gt=0, description="Identificador da matéria/conteúdo"),
]


class CommentCreate(BaseModel):
    """Payload para criação de comentário."""

    email: EmailStr = Field(
        ...,
        description="Email do autor do comentário",
        examples=["devops@example.com"],
    )
    comment: NonEmptyComment = Field(
        ...,
        examples=["Excelente artigo sobre Kubernetes!"],
    )
    content_id: PositiveContentId = Field(..., examples=[42])


class CommentResponse(BaseModel):
    """Representação pública de um comentário."""

    model_config = ConfigDict(from_attributes=True)

    id: int = Field(..., description="ID único do comentário")
    email: EmailStr = Field(..., description="Email do autor")
    comment: str = Field(..., description="Texto do comentário")
    content_id: int = Field(..., description="Identificador da matéria/conteúdo")
    created_at: datetime = Field(..., description="Timestamp de criação")


class HealthResponse(BaseModel):
    """Resposta de readiness / health legado."""

    status: Literal["healthy", "ready", "unhealthy", "not_ready"] = Field(
        ...,
        description="Status da aplicação",
    )
    database: Literal["connected", "disconnected"] = Field(
        ...,
        description="Status da conexão com banco",
    )
    version: str = Field(..., description="Versão da aplicação")


class LivenessResponse(BaseModel):
    """Resposta de liveness (processo vivo)."""

    status: Literal["alive"] = "alive"
    version: str = Field(..., description="Versão da aplicação")
