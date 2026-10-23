"""Testes de integração HTTP da Comments API."""

from __future__ import annotations

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_health_check(client: AsyncClient) -> None:
    response = await client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert data["database"] == "connected"
    assert "version" in data


@pytest.mark.asyncio
async def test_liveness_check(client: AsyncClient) -> None:
    response = await client.get("/health/live")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "alive"
    assert "version" in data


@pytest.mark.asyncio
async def test_readiness_check(client: AsyncClient) -> None:
    response = await client.get("/health/ready")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ready"
    assert data["database"] == "connected"
    assert "version" in data


@pytest.mark.asyncio
async def test_metrics_endpoint(client: AsyncClient) -> None:
    response = await client.get("/metrics")
    assert response.status_code == 200
    assert "text/plain" in response.headers.get("content-type", "")
    assert "http_requests" in response.text or "python_info" in response.text


@pytest.mark.asyncio
async def test_create_comment_success(client: AsyncClient) -> None:
    payload = {
        "email": "devops.sr@example.com",
        "comment": "Infraestrutura resiliente e código limpo.",
        "content_id": 101,
    }
    response = await client.post("/api/comment/new", json=payload)
    assert response.status_code == 201
    data = response.json()
    assert data["id"] > 0
    assert data["email"] == payload["email"]
    assert data["comment"] == payload["comment"]
    assert data["content_id"] == payload["content_id"]
    assert "created_at" in data


@pytest.mark.asyncio
async def test_create_comment_invalid_email(client: AsyncClient) -> None:
    payload = {
        "email": "not-an-email",
        "comment": "Teste com email inválido.",
        "content_id": 101,
    }
    response = await client.post("/api/comment/new", json=payload)
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_create_comment_empty_text(client: AsyncClient) -> None:
    payload = {
        "email": "dev@example.com",
        "comment": "",
        "content_id": 101,
    }
    response = await client.post("/api/comment/new", json=payload)
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_list_comments_by_content_id(client: AsyncClient) -> None:
    for email, text, content_id in (
        ("user1@example.com", "Primeiro comentário", 200),
        ("user2@example.com", "Segundo comentário", 200),
        ("user3@example.com", "Outro assunto", 300),
    ):
        await client.post(
            "/api/comment/new",
            json={"email": email, "comment": text, "content_id": content_id},
        )

    response_200 = await client.get("/api/comment/list/200")
    assert response_200.status_code == 200
    comments_200 = response_200.json()
    assert len(comments_200) == 2
    assert all(item["content_id"] == 200 for item in comments_200)

    response_300 = await client.get("/api/comment/list/300")
    assert response_300.status_code == 200
    comments_300 = response_300.json()
    assert len(comments_300) == 1
    assert comments_300[0]["content_id"] == 300

    response_empty = await client.get("/api/comment/list/9999")
    assert response_empty.status_code == 200
    assert response_empty.json() == []
