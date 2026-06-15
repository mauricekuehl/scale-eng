#!/usr/bin/env bash
set -euo pipefail

readonly PROFILE_STEADY="steady"
readonly PROFILE_SPIKE="spike"
readonly PROFILE_BREAKPOINT="breakpoint"
readonly MODE_QUERY="query"
readonly MODE_READ="read"
readonly DISTRIBUTION_CONSTANT="constant"
readonly DISTRIBUTION_UNIFORM="uniform"
readonly DISTRIBUTION_HOTSPOT="hotspot"

usage() {
  cat <<'USAGE'
Usage:
  API_URL=http://localhost:8080 ./load-tests/run.sh --steady|--spike|--breakpoint --query
  API_URL=http://localhost:8080 ./load-tests/run.sh --steady|--spike|--breakpoint --read --constant-distribution|--uniform-distribution|--hotspot-distribution

Options:
  --steady                  Moderate constant load.
  --spike                   Fast ramp to high load, then ramp down.
  --breakpoint              Slowly increase load until thresholds fail or max load is reached.
  --query                   Load test POST /create with unique URLs.
  --read                    Seed entries, then load test GET /<code>.
  --constant-distribution   Always read the first seeded code.
  --uniform-distribution    Read evenly across seeded codes.
  --hotspot-distribution    Read with a simple hot-key skew.

Environment:
  API_URL      Required. Base URL of the API under test.
  SEED_COUNT   Optional for --read. Defaults to 1000.
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
    --query|--read)
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

if [[ "$mode" == "$MODE_READ" && -z "$distribution" ]]; then
  echo "error: --read requires a distribution" >&2
  usage >&2
  exit 2
fi

if [[ "$mode" == "$MODE_QUERY" && -n "$distribution" ]]; then
  echo "error: distributions are only valid with --read" >&2
  usage >&2
  exit 2
fi

if ! command -v k6 >/dev/null 2>&1; then
  echo "error: k6 is required but was not found in PATH" >&2
  exit 127
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$script_dir/$mode.js"

args=(-e "API_URL=$API_URL" -e "PROFILE=$profile")
if [[ "$mode" == "$MODE_READ" ]]; then
  args+=(-e "DISTRIBUTION=$distribution")
fi

k6 run "${args[@]}" "$script"
