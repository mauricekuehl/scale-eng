import importlib.util
from collections.abc import Callable, Sequence
from pathlib import Path
from typing import cast

PROJECT_ROOT = Path(__file__).resolve().parents[1]
SHARDING_PATH = PROJECT_ROOT / "services" / "api" / "sharding.py"

ReplicaSelector = Callable[[str, Sequence[str], int], tuple[str, ...]]


def load_replica_shards_for_key() -> ReplicaSelector:
    spec = importlib.util.spec_from_file_location("api_sharding", SHARDING_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {SHARDING_PATH}")

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return cast(ReplicaSelector, module.replica_shards_for_key)


replica_shards_for_key = load_replica_shards_for_key()


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
