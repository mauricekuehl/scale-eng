import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT / "services" / "api"))

from sharding import replica_shards_for_key


def test_replica_set_is_stable_and_bounded() -> None:
    shards = (
        "http://db-1:9000",
        "http://db-2:9000",
        "http://db-3:9000",
        "http://db-4:9000",
    )

    first = replica_shards_for_key("7Dw8Ew42", shards, 2)
    second = replica_shards_for_key("7Dw8Ew42", shards, 2)

    assert first == second
    assert len(first) == 2
    assert len(set(first)) == 2
    assert set(first).issubset(shards)


def test_replica_set_caps_at_available_shards() -> None:
    shards = ("http://db-1:9000",)

    assert replica_shards_for_key("7Dw8Ew42", shards, 2) == shards
