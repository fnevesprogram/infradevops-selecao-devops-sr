"""Roteadores HTTP da Comments API."""

from app.src.routers.comments import register_comments_routes
from app.src.routers.health import register_health_routes

__all__ = ("register_comments_routes", "register_health_routes")
