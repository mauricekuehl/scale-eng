import hashlib
from collections.abc import Sequence


def _rendezvous_score(key: str, shard: str) -> bytes:
    # Rendezvous hashing: the top-k shards by score form the replica set.
    return hashlib.sha256(f"{key}\0{shard}".encode()).digest()


def replica_shards_for_key(key: str, shards: Sequence[str], replica_count: int) -> tuple[str, ...]:
    if replica_count < 1:
        raise ValueError("replica_count must be at least 1")
    if not shards:
        return ()

    ordered = sorted(shards, key=lambda shard: _rendezvous_score(key, shard), reverse=True)
    return tuple(ordered[: min(replica_count, len(ordered))])
