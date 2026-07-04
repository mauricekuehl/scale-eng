"""
Self-implemented overload protection.

* ``Bulkhead`` -- bounds the concurrency a single API node imposes on a
  downstream dependency (the DB, later a shard). With ``N`` nodes each capped
  at ``limit`` the downstream sees at most ``N * limit`` in-flight calls, so
  scaling the API tier out cannot overload the shared component.
* ``CircuitBreaker`` -- stops hammering a downstream that is already failing so
  it can recover, failing fast in the meantime. One instance per downstream
  (later: one per shard).

Both guards reject fast (fail-fast) instead of queuing unbounded work; the
caller turns a rejection into an HTTP 503 + ``Retry-After`` (backpressure)
rather than letting load cascade.
"""

import asyncio
import time
from collections.abc import Awaitable, Callable, Iterable
from typing import TypeVar

T = TypeVar("T")


class OverloadError(Exception):
    """Raised when a guard rejects work to protect a downstream from overload."""

    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason


class Bulkhead:
    """Bound the concurrency a node imposes on one downstream dependency."""

    def __init__(self, limit: int, acquire_timeout: float) -> None:
        self.limit = limit
        self.acquire_timeout = acquire_timeout
        self._slots = asyncio.Semaphore(limit)
        self.in_use = 0  # slots currently held (for metrics)
        self.rejected = 0  # cumulative calls rejected because no slot was free

    async def run(self, work: Callable[[], Awaitable[T]]) -> T:
        try:
            await asyncio.wait_for(self._slots.acquire(), self.acquire_timeout)
        except TimeoutError:
            self.rejected += 1
            raise OverloadError("downstream bulkhead full") from None
        self.in_use += 1
        try:
            return await work()
        finally:
            self.in_use -= 1
            self._slots.release()


class CircuitBreaker:
    def __init__(self, failure_threshold: int, cooldown: float) -> None:
        self.failure_threshold = failure_threshold
        self.cooldown = cooldown
        self.failures = 0
        self.opened_at = 0.0
        self.short_circuited = 0  # cumulative calls rejected while OPEN

    def allow(self) -> bool:
        if self.failures < self.failure_threshold:
            return True  # CLOSED
        # OPEN: reject until the cooldown elapses, then let one probe through
        # (HALF_OPEN). A successful probe closes the breaker via record_success.
        if time.monotonic() - self.opened_at >= self.cooldown:
            return True
        self.short_circuited += 1
        return False

    def record_success(self) -> None:
        self.failures = 0

    def record_failure(self) -> None:
        self.failures += 1
        self.opened_at = time.monotonic()

    @property
    def is_open(self) -> bool:
        return self.failures >= self.failure_threshold
