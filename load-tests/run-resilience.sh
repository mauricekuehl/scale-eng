#!/usr/bin/env bash
set -euo pipefail

# Resilience suite for requirement 3 (overload mitigation). Spike profiles slam
# the system with a sudden load increase to show it degrades gracefully and does
# not overload a downstream component. This is a behaviour demo, not a capacity
# measurement, so keep it separate from the core scaling suite.

usage() {
  cat <<'USAGE'
Usage:
  API_URL=http://localhost:8080 ./load-tests/run-resilience.sh [label]

Arguments:
  label   Optional. Results are written to ./benchmarks/<label>/.

Environment:
  API_URL         Required. Base URL of the API under test.
  SPIKE_PEAK_VUS  Optional. Peak VUs of the spike (default 100).
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

run_test --spike --query
run_test --breakpoint --read  --hotspot-distribution

echo ""
if [[ ${#failed[@]} -eq 0 ]]; then
  echo "Resilience suite completed. Results: $BENCHMARK_DIR"
else
  echo "${#failed[@]} test(s) failed:"
  for f in "${failed[@]}"; do
    echo "  - $f"
  done
  exit 1
fi
