from collections.abc import Iterable

from cache import LRUCache
from collections.abc import Callable, Iterable
from overload import Bulkhead, CircuitBreaker
from opentelemetry.metrics import CallbackOptions, Meter, Observation


def instrument_cache(meter: Meter, cache: LRUCache) -> None:
    """
    Register OTLP observable counters reading the cache's hit/miss totals
    """

    def hits_callback(options: CallbackOptions) -> Iterable[Observation]:
        yield Observation(cache.hits)

    def misses_callback(options: CallbackOptions) -> Iterable[Observation]:
        yield Observation(cache.misses)

    meter.create_observable_counter(
        "cache.hits",
        callbacks=[hits_callback],
        description="Cumulative read-cache hits.",
    )
    meter.create_observable_counter(
        "cache.misses",
        callbacks=[misses_callback],
        description="Cumulative read-cache misses.",
    )

def instrument_overload(meter: Meter, bulkhead: Bulkhead, breaker: CircuitBreaker) -> None:
    """Expose the guards' counters as OTLP metrics (mirrors instrument_cache)."""

    def observe(value_fn: Callable[[], int | float]) -> Callable[..., Iterable[Observation]]:
        def callback(options: CallbackOptions) -> Iterable[Observation]:
            yield Observation(value_fn())

        return callback

    meter.create_observable_counter(
        "overload.bulkhead.rejected",
        callbacks=[observe(lambda: bulkhead.rejected)],
        description="Cumulative DB calls rejected because the bulkhead was full.",
    )
    meter.create_observable_gauge(
        "overload.bulkhead.in_use",
        callbacks=[observe(lambda: bulkhead.in_use)],
        description="DB-call slots currently in use on this node.",
    )
    meter.create_observable_counter(
        "overload.circuit.short_circuited",
        callbacks=[observe(lambda: breaker.short_circuited)],
        description="Cumulative DB calls rejected while the circuit was open.",
    )
    meter.create_observable_gauge(
        "overload.circuit.open",
        callbacks=[observe(lambda: int(breaker.is_open))],
        description="1 while the DB circuit breaker is open, else 0.",
    )
