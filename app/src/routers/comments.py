"""Endpoints de criação e listagem de comentários."""

from __future__ import annotations

import logging
from typing import Annotated

from fastapi import Depends, FastAPI, Path, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.src.database import get_db
from app.src.models import Comment
from app.src.schemas import CommentCreate, CommentResponse

logger = logging.getLogger(__name__)

DbSession = Annotated[AsyncSession, Depends(get_db)]
ContentIdPath = Annotated[
    int,
    Path(gt=0, description="Identificador da matéria (content_id)"),
]


def register_comments_routes(app: FastAPI) -> None:
    """Registra rotas de comentários diretamente no app."""

    @app.post(
        "/api/comment/new",
        response_model=CommentResponse,
        status_code=status.HTTP_201_CREATED,
        tags=["Comments"],
        summary="Inserir um novo comentário em uma matéria",
    )
    async def create_comment(
        payload: CommentCreate,
        db: DbSession,
    ) -> CommentResponse:
        comment = Comment(**payload.model_dump())
        db.add(comment)
        await db.commit()
        await db.refresh(comment)

        logger.info(
            "Created comment id=%s content_id=%s",
            comment.id,
            comment.content_id,
        )
        return CommentResponse.model_validate(comment)

    @app.get(
        "/api/comment/list/{id}",
        response_model=list[CommentResponse],
        status_code=status.HTTP_200_OK,
        tags=["Comments"],
        summary="Listar comentários de uma matéria específica",
    )
    async def list_comments(
        id: ContentIdPath,
        db: DbSession,
    ) -> list[CommentResponse]:
        content_id = id
        stmt = (
            select(Comment)
            .where(Comment.content_id == content_id)
            .order_by(Comment.created_at.desc())
        )
        comments = (await db.scalars(stmt)).all()
        return [CommentResponse.model_validate(row) for row in comments]
