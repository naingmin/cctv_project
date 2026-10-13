"""Shared/common schemas."""
from __future__ import annotations

from typing import Generic, List, TypeVar

from pydantic import BaseModel

T = TypeVar("T")


class PaginationMeta(BaseModel):
    page: int
    limit: int
    total: int
    pages: int
    has_next: bool


class Paginated(BaseModel, Generic[T]):
    items: List[T]
    pagination: PaginationMeta


class MessageResponse(BaseModel):
    message: str
