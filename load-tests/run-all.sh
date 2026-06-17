#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  API_URL=http://localhost:8080 ./load-tests/run-all.sh [label]

Arguments:
  label   Optional. Results are written to ./benchmarks/<label>/.
          Use distinct labels to compare runs, e.g. "before-scaling" and "after-scaling".
          If omitted, results go directly to ./benchmarks/.

Environment:
  API_URL  Required. Base URL of the API under test.
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
    # Prometheus scrapes every 15s; waiting 30s gives it two chances to collect
    # post-run metrics before the next benchmark changes the load profile.
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

# Query
run_test --steady     --query
run_test --spike      --query
run_test --breakpoint --query

# Read
for dist in --uniform-distribution --hotspot-distribution --constant-distribution; do
  run_test --steady     --read "$dist"
  run_test --spike      --read "$dist"
  run_test --breakpoint --read "$dist"
done

# Mixed
for dist in --uniform-distribution --hotspot-distribution --constant-distribution; do
  run_test --steady     --mixed "$dist"
  run_test --spike      --mixed "$dist"
  run_test --breakpoint --mixed "$dist"
done

echo ""
if [[ ${#failed[@]} -eq 0 ]]; then
  echo "All tests completed. Results: $BENCHMARK_DIR"
else
  echo "${#failed[@]} test(s) failed:"
  for f in "${failed[@]}"; do
    echo "  - $f"
  done
  exit 1
fi
