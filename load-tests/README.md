# Load Tests

These tests answer one question for the scalability assignment:

> **What is the maximum throughput (req/s) this configuration can sustain while
> staying within the SLO?**

That number is the performance metric that should grow as we scale out (1 → 3 →
5 nodes) and shard the DB. Everything here is built so the same benchmark keeps
revealing a higher ceiling as the system gets faster.

## Why an open model

Capacity must be measured with an **open model** (`ramping-arrival-rate`), which
injects requests at a fixed rate regardless of how fast the system responds. A
closed model (`constant-vus`) caps throughput at `VUs / latency`, so making the
system faster barely changes the number — it cannot show scaling. The `breakpoint`
profile ramps the arrival rate up until the SLO breaks; a sharded/scaled system
reaches a higher rate before that happens.

## SLO

Capacity = highest throughput where **both** hold:

| Metric | Default | Env override |
|--------|---------|--------------|
| p95 latency | < 500 ms | `SLO_P95_MS` |
| error rate  | < 1 %    | `SLO_ERROR_RATE` |

500 ms is a placeholder. After the first real run, set `SLO_P95_MS` to something
meaningful for the deployment (well above network RTT noise, well below the point
where requests are clearly queueing). Keep it identical across all configs.

## Benchmarks

| Mode / distribution | Stresses | Insight |
|---------------------|----------|---------|
| `--query` | Write path: code generation + DB `PUT` under the DB's global lock | Write throughput ceiling. Worst lock contention. |
| `--read --uniform` | Read path, keys spread evenly | Best-case read scaling — should rise ~linearly when reads are sharded. |
| `--read --hotspot` | Read path, 80 % of reads hit 20 % of keys | Whether a hot shard caps throughput despite more nodes. |
| `--read --constant` | All reads hit one key | Single-key / single-shard worst case (cache/lock hotspot). |
| `--mixed --hotspot` | Realistic 90 % read / 10 % write + hotspot | Closest to production; the headline realistic number. |

Load profiles:

| Profile | Executor | Purpose |
|---------|----------|---------|
| `--breakpoint` | `ramping-arrival-rate` (open) | **Capacity.** Ramps until the SLO breaks. The metric for scaling. |
| `--spike` | `ramping-vus` | Overload mitigation (requirement 3): sudden surge, graceful degradation. |
| `--steady` | `constant-vus` (closed) | Sanity check only. **Not** a scaling metric. |

## Suites

```bash
export API_URL="$(terraform -chdir=infra output -raw base_url)"

# Core scaling suite: 3 breakpoint runs, ~30 min. Label with the node count.
./load-tests/run-core.sh 1-node
./load-tests/run-core.sh 3-node
./load-tests/run-core.sh 5-node

# Resilience suite (requirement 3): spike behaviour.
./load-tests/run-resilience.sh 3-node

# Full matrix (all profiles × modes × distributions, ~2 h). Rarely needed.
./load-tests/run-all.sh some-label
```

For cloud runs, `make restart-db` between runs to clear the in-memory DB.

## Calibrating the breakpoint ramp

The ramp ceiling must sit a bit *above* the capacity of your **strongest**
configuration, so even the fastest config hits its knee inside the run (and weaker
configs abort earlier — exactly the signal we want).

1. Run once against the strongest config (e.g. 5-node) with a high ceiling:
   ```bash
   BREAKPOINT_RATE_MAX=2000 ./load-tests/run-core.sh calibrate
   ```
2. Open the generated `*-report.html` and read the arrival rate at the point where
   p95 crosses the SLO. That is roughly its capacity.
3. Set `BREAKPOINT_RATE_MAX` to ~1.5× that value and keep it fixed for all real
   runs so every configuration is measured on the same scale:
   ```bash
   export BREAKPOINT_RATE_MAX=...   # e.g. 1200
   ```

Other knobs (all optional env vars): `BREAKPOINT_RAMP` (default `8m`),
`BREAKPOINT_RATE_START`, `BREAKPOINT_MAX_VUS`, `SEED_COUNT` (default 5000),
`SPIKE_PEAK_VUS`. See [config.js](config.js).

## Graphs

Each run writes a self-contained `*-report.html` (k6 web dashboard) with the
**latency and throughput time series** — use it to read the saturation knee and
as a presentation screenshot. Set `K6_TIMESERIES=1` to additionally export raw
per-sample JSON (large) if you want to compute the exact capacity number.

Cross-configuration comparison:

```bash
python analyze.py
```

With node-count labels (`1-node`, `3-node`, `5-node`) this writes
`benchmarks/report.png` including a **throughput-vs-configuration scaling curve** —
the headline slide.

## Known limitation worth stating in the talk

The API and DB services are single-process async Python: one process uses one CPU
core. Vertical scaling (bigger machines, bonus 2d) therefore yields little unless
multiple worker processes/containers run per node. Throughput scaling comes mainly
from scaling **out** and sharding the DB to remove the single global-lock
bottleneck in [services/db/app.py](../services/db/app.py).
