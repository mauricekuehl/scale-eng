#!/usr/bin/env bash
set -euo pipefail

# Core scaling suite. Three breakpoint runs that answer "how much throughput can
# this configuration sustain at the SLO?" — the one number that should grow as
# you scale out / shard. Runs in ~30 min, unlike the full matrix in run-all.sh.
#
#   read --uniform   : best-case read scaling, spread evenly across shards
#   query            : write scaling, the path with the most lock contention
#   mixed --hotspot  : realistic 90/10 mix + the hotspot edge case for sharding
#
# Calibrate once against your strongest config (see load-tests/README.md), then
# keep BREAKPOINT_RATE_MAX fixed so every configuration is comparable.

usage() {
  cat <<'USAGE'
Usage:
  API_URL=http://localhost:8080 ./load-tests/run-core.sh [label]

Arguments:
  label   Optional. Results are written to ./benchmarks/<label>/.
          Use the node count as the label, e.g. "1-node", "3-node", "5-node",
          so analyze.py can plot the scaling curve across configurations.

Environment:
  API_URL              Required. Base URL of the API under test.
  BREAKPOINT_RATE_MAX  Optional. Ceiling of the arrival-rate ramp (default 500).
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -z "${API_URL:-}" ]]; then
  echo "error: API_URL is required" >&2
  usage >&2
  exit 2
fi

label="${1:-}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/.." && pwd)"

if [[ -n "$label" ]]; then
  export BENCHMARK_DIR="$repo_dir/benchmarks/$label"
else
  export BENCHMARK_DIR="$repo_dir/benchmarks"
fi

failed=()
has_run_test=0
readonly prometheus_settle_seconds=30

run_test() {
  if [[ "$has_run_test" -eq 1 ]]; then
    echo ""
    echo "Waiting ${prometheus_settle_seconds}s for Prometheus to scrape..."
    sleep "$prometheus_settle_seconds"
  fi
  has_run_test=1

  echo ""
  echo "==> $*"
  if ! "$script_dir/run.sh" "$@"; then
    echo "FAILED: $*" >&2
    failed+=("$*")
  fi
}

run_test --breakpoint --read  --uniform-distribution
run_test --breakpoint --query
run_test --breakpoint --mixed --hotspot-distribution

echo ""
if [[ ${#failed[@]} -eq 0 ]]; then
  echo "Core suite completed. Results: $BENCHMARK_DIR"
else
  echo "${#failed[@]} test(s) failed:"
  for f in "${failed[@]}"; do
    echo "  - $f"
  done
  exit 1
fi
