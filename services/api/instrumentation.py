from collections.abc import Callable, Iterable

from cache import LRUCache
from opentelemetry.metrics import CallbackOptions, Meter, Observation
from overload import ShardGuards


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


def instrument_overload(meter: Meter, guards: ShardGuards) -> None:
    """Expose each shard's guard counters as per-shard OTLP metrics (attribute `shard`)."""

    def per_shard(
        value_fn: Callable[[str], int | float],
    ) -> Callable[..., Iterable[Observation]]:
        def callback(options: CallbackOptions) -> Iterable[Observation]:
            for shard in guards.shards:
                yield Observation(value_fn(shard), {"shard": shard})

        return callback

    meter.create_observable_counter(
        "overload.bulkhead.rejected",
        callbacks=[per_shard(lambda s: guards.bulkheads[s].rejected)],
        description="Cumulative DB calls rejected because a shard's bulkhead was full.",
    )
    meter.create_observable_gauge(
        "overload.bulkhead.in_use",
        callbacks=[per_shard(lambda s: guards.bulkheads[s].in_use)],
        description="DB-call slots currently in use per shard on this node.",
    )
    meter.create_observable_counter(
        "overload.circuit.short_circuited",
        callbacks=[per_shard(lambda s: guards.breakers[s].short_circuited)],
        description="Cumulative DB calls rejected while a shard's circuit was open.",
    )
    meter.create_observable_gauge(
        "overload.circuit.open",
        callbacks=[per_shard(lambda s: int(guards.breakers[s].is_open))],
        description="1 while a shard's circuit breaker is open, else 0.",
    )
