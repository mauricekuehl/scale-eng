#!/usr/bin/env bash
set -euo pipefail

readonly PROFILE_STEADY="steady"
readonly PROFILE_SPIKE="spike"
readonly PROFILE_BREAKPOINT="breakpoint"
readonly MODE_QUERY="query"
readonly MODE_READ="read"
readonly MODE_MIXED="mixed"
readonly DISTRIBUTION_CONSTANT="constant"
readonly DISTRIBUTION_UNIFORM="uniform"
readonly DISTRIBUTION_HOTSPOT="hotspot"

usage() {
  cat <<'USAGE'
Usage:
  API_URL=http://localhost:8080 ./load-tests/run.sh --steady|--spike|--breakpoint --query
  API_URL=http://localhost:8080 ./load-tests/run.sh --steady|--spike|--breakpoint --read --constant-distribution|--uniform-distribution|--hotspot-distribution
  API_URL=http://localhost:8080 ./load-tests/run.sh --steady|--spike|--breakpoint --mixed --constant-distribution|--uniform-distribution|--hotspot-distribution

Options:
  --steady                  Moderate constant load.
  --spike                   Fast ramp to high load, then ramp down.
  --breakpoint              Slowly increase load until thresholds fail or max load is reached.
  --query                   Load test POST /create with unique URLs.
  --read                    Seed entries, then load test GET /<code>.
  --mixed                   Seed entries, then load test 90% GET /<code> and 10% POST /create.
  --constant-distribution   Always read the first seeded code.
  --uniform-distribution    Read evenly across seeded codes.
  --hotspot-distribution    Read with a hotspot distribution: 80% of requests read the top 20% of seeded codes.

Environment:
  API_URL      Required. Base URL of the API under test.
  BENCHMARK_DIR Optional output directory. Defaults to ./benchmarks.
  K6_TIMESERIES Optional. Set to 1 to also export raw time-series JSON (large).
USAGE
}

profile=""
mode=""
distribution=""

for arg in "$@"; do
  case "$arg" in
    --steady|--spike|--breakpoint)
      if [[ -n "$profile" ]]; then
        echo "error: choose exactly one load profile" >&2
        usage >&2
        exit 2
      fi
      case "$arg" in
        --steady)
          profile="$PROFILE_STEADY"
          ;;
        --spike)
          profile="$PROFILE_SPIKE"
          ;;
        --breakpoint)
          profile="$PROFILE_BREAKPOINT"
          ;;
      esac
      ;;
    --query|--read|--mixed)
      if [[ -n "$mode" ]]; then
        echo "error: choose exactly one test mode" >&2
        usage >&2
        exit 2
      fi
      case "$arg" in
        --query)
          mode="$MODE_QUERY"
          ;;
        --read)
          mode="$MODE_READ"
          ;;
        --mixed)
          mode="$MODE_MIXED"
          ;;
      esac
      ;;
    --constant-distribution)
      if [[ -n "$distribution" ]]; then
        echo "error: choose exactly one read distribution" >&2
        usage >&2
        exit 2
      fi
      distribution="$DISTRIBUTION_CONSTANT"
      ;;
    --uniform-distribution)
      if [[ -n "$distribution" ]]; then
        echo "error: choose exactly one read distribution" >&2
        usage >&2
        exit 2
      fi
      distribution="$DISTRIBUTION_UNIFORM"
      ;;
    --hotspot-distribution)
      if [[ -n "$distribution" ]]; then
        echo "error: choose exactly one read distribution" >&2
        usage >&2
        exit 2
      fi
      distribution="$DISTRIBUTION_HOTSPOT"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${API_URL:-}" ]]; then
  echo "error: API_URL is required" >&2
  exit 2
fi

if [[ -z "$profile" ]]; then
  echo "error: choose exactly one load profile" >&2
  usage >&2
  exit 2
fi

if [[ -z "$mode" ]]; then
  echo "error: choose exactly one test mode" >&2
  usage >&2
  exit 2
fi

if [[ ("$mode" == "$MODE_READ" || "$mode" == "$MODE_MIXED") && -z "$distribution" ]]; then
  echo "error: --${mode} requires a distribution" >&2
  usage >&2
  exit 2
fi

if [[ "$mode" == "$MODE_QUERY" && -n "$distribution" ]]; then
  echo "error: distributions are only valid with --read and --mixed" >&2
  usage >&2
  exit 2
fi

if ! command -v k6 >/dev/null 2>&1; then
  echo "error: k6 is required but was not found in PATH" >&2
  exit 127
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$script_dir/$mode.js"
repo_dir="$(cd "$script_dir/.." && pwd)"
benchmark_dir="${BENCHMARK_DIR:-$repo_dir/benchmarks}"
timestamp="$(date -u +"%Y%m%dT%H%M%SZ")"
benchmark_name="$timestamp-$profile-$mode"
if [[ "$mode" == "$MODE_READ" || "$mode" == "$MODE_MIXED" ]]; then
  benchmark_name="$benchmark_name-$distribution"
fi
benchmark_file="$benchmark_dir/$benchmark_name-summary.json"
report_file="$benchmark_dir/$benchmark_name-report.html"

mkdir -p "$benchmark_dir"

args=(-e "API_URL=$API_URL" -e "PROFILE=$profile")
if [[ "$mode" == "$MODE_READ" || "$mode" == "$MODE_MIXED" ]]; then
  args+=(-e "DISTRIBUTION=$distribution")
fi

outputs=()
if [[ "${K6_TIMESERIES:-0}" == "1" ]]; then
  timeseries_file="$benchmark_dir/$benchmark_name-timeseries.json.gz"
  outputs+=(--out "json=$timeseries_file")
  echo "Writing time-series JSON to $timeseries_file"
fi

echo "Writing k6 summary to $benchmark_file"
echo "Writing k6 HTML report to $report_file"
if [[ "${K6_TIMESERIES:-0}" == "1" ]]; then
  K6_WEB_DASHBOARD=true \
  K6_WEB_DASHBOARD_EXPORT="$report_file" \
    k6 run --summary-export "$benchmark_file" "${outputs[@]}" "${args[@]}" "$script"
else
  K6_WEB_DASHBOARD=true \
  K6_WEB_DASHBOARD_EXPORT="$report_file" \
    k6 run --summary-export "$benchmark_file" "${args[@]}" "$script"
fi
