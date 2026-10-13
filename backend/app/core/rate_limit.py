"""Simple in-process rate limiter.

A token-bucket limiter keyed by client identity. Suitable for a single node;
behind multiple replicas, back this with Redis or an API gateway instead.
"""
from __future__ import annotations

import threading
import time
from dataclasses import dataclass

from fastapi import Request

from app.core.errors import RateLimitError


@dataclass
class _Bucket:
    tokens: float
    last_refill: float


class RateLimiter:
    def __init__(self, *, capacity: int, refill_per_second: float) -> None:
        self.capacity = capacity
        self.refill_per_second = refill_per_second
        self._buckets: dict[str, _Bucket] = {}
        self._lock = threading.Lock()

    def check(self, key: str) -> None:
        now = time.monotonic()
        with self._lock:
            bucket = self._buckets.get(key)
            if bucket is None:
                bucket = _Bucket(tokens=self.capacity, last_refill=now)
                self._buckets[key] = bucket

            elapsed = now - bucket.last_refill
            bucket.tokens = min(
                self.capacity,
                bucket.tokens + elapsed * self.refill_per_second,
            )
            bucket.last_refill = now
            if bucket.tokens < 1:
                raise RateLimitError()
            bucket.tokens -= 1

            # Opportunistically evict stale buckets.
            if len(self._buckets) > 10_000:
                cutoff = now - 600
                for k in [
                    k for k, b in self._buckets.items() if b.last_refill < cutoff
                ]:
                    self._buckets.pop(k, None)


def client_identity(request: Request) -> str:
    if request.client and request.client.host:
        return request.client.host
    return "unknown"


# Conservative defaults; tune per environment.
_login_limiter = RateLimiter(capacity=10, refill_per_second=0.2)
_sensitive_limiter = RateLimiter(capacity=30, refill_per_second=0.5)


def enforce_login_rate_limit(request: Request) -> None:
    _login_limiter.check(f"login:{client_identity(request)}")


def enforce_sensitive_rate_limit(request: Request) -> None:
    _sensitive_limiter.check(f"sensitive:{client_identity(request)}")


def reset_limiters() -> None:
    """Clear all buckets. Intended for tests."""
    with _login_limiter._lock:
        _login_limiter._buckets.clear()
    with _sensitive_limiter._lock:
        _sensitive_limiter._buckets.clear()
