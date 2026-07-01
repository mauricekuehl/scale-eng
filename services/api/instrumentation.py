from collections.abc import Iterable

from cache import LRUCache
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
