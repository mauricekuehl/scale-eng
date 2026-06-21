// Central tuning surface for all load tests.
//
// The headline metric is "maximum sustained throughput while the SLO holds".
// The breakpoint profile ramps an open-model arrival rate upward until the SLO
// is breached, so a faster system (e.g. after sharding the DB) reaches a higher
// rate before aborting. Calibrate BREAKPOINT_RATE_MAX against your *strongest*
// configuration once, then keep it fixed so every config is comparable.
//
// All knobs below can be overridden via environment variables (k6 `-e NAME=...`).

function num(name, fallback) {
  const value = Number(__ENV[name]);
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

// --- SLO: defines what "acceptable" means. Capacity = max throughput while both hold. ---
const SLO_P95_MS = num("SLO_P95_MS", 500);
const SLO_ERROR_RATE = (() => {
  const value = Number(__ENV.SLO_ERROR_RATE);
  return Number.isFinite(value) && value >= 0 ? value : 0.01;
})();

// --- Breakpoint ramp. Calibrate RATE_MAX so the strongest config breaches the SLO
//     a little before the ramp ends (so you can read the knee off the graph). ---
const BREAKPOINT_RATE_START = num("BREAKPOINT_RATE_START", 25);
const BREAKPOINT_RATE_MAX = num("BREAKPOINT_RATE_MAX", 500);
const BREAKPOINT_RAMP = __ENV.BREAKPOINT_RAMP || "8m";
// VUs must never be the bottleneck, or k6 reports a generator limit as if the
// system saturated. Keep this generous relative to RATE_MAX.
const BREAKPOINT_MAX_VUS = num("BREAKPOINT_MAX_VUS", Math.max(1000, BREAKPOINT_RATE_MAX * 2));

// --- Spike: used for the overload-mitigation demo (requirement 3), not for capacity. ---
const SPIKE_PEAK = num("SPIKE_PEAK_VUS", 100);
const SPIKE_BASE = num("SPIKE_BASE_VUS", 20);

// --- Steady: closed-model sanity check only. Not a scaling metric. ---
const STEADY_VUS = num("STEADY_VUS", 20);
const STEADY_DURATION = __ENV.STEADY_DURATION || "2m";

// --- Seeding for read/mixed. Enough keys to spread reads across shards. ---
const SEED_COUNT = num("SEED_COUNT", 5000);
const SEED_BATCH_SIZE = num("SEED_BATCH_SIZE", 100);

function sloThresholds(abortOnFail) {
  return {
    http_req_failed: [
      { threshold: `rate<${SLO_ERROR_RATE}`, abortOnFail, delayAbortEval: "30s" },
    ],
    http_req_duration: [
      { threshold: `p(95)<${SLO_P95_MS}`, abortOnFail, delayAbortEval: "30s" },
    ],
  };
}

// One profile definition shared by query/read/mixed so parameters live in a single place.
function makeProfiles() {
  return {
    steady: {
      scenarios: {
        steady: {
          executor: "constant-vus",
          vus: STEADY_VUS,
          duration: STEADY_DURATION,
        },
      },
      thresholds: sloThresholds(false),
    },
    spike: {
      scenarios: {
        spike: {
          executor: "ramping-vus",
          stages: [
            { duration: "15s", target: SPIKE_BASE },
            { duration: "30s", target: SPIKE_PEAK },
            { duration: "1m", target: SPIKE_PEAK },
            { duration: "30s", target: 0 },
          ],
        },
      },
      thresholds: sloThresholds(false),
    },
    breakpoint: {
      scenarios: {
        breakpoint: {
          executor: "ramping-arrival-rate",
          timeUnit: "1s",
          startRate: BREAKPOINT_RATE_START,
          preAllocatedVUs: Math.min(BREAKPOINT_MAX_VUS, 200),
          maxVUs: BREAKPOINT_MAX_VUS,
          // Single linear ramp from start -> max. abortOnFail stops the run at the
          // knee, so the arrival rate at abort time approximates the capacity.
          stages: [{ duration: BREAKPOINT_RAMP, target: BREAKPOINT_RATE_MAX }],
        },
      },
      thresholds: sloThresholds(true),
    },
  };
}

const distributions = {
  constant: {
    pickIndex: () => 0,
  },
  uniform: {
    pickIndex: (size) => Math.floor(Math.random() * size),
  },
  hotspot: {
    pickIndex: (size) => {
      if (Math.random() < 0.8) {
        return Math.floor(Math.random() * (size * 0.2));
      }
      return Math.floor(Math.random() * size);
    },
  },
};

export const config = Object.freeze({
  query: {
    profiles: makeProfiles(),
  },
  read: {
    seedCount: SEED_COUNT,
    seedBatchSize: SEED_BATCH_SIZE,
    profiles: makeProfiles(),
    distributions,
  },
  mixed: {
    seedCount: SEED_COUNT,
    seedBatchSize: SEED_BATCH_SIZE,
    profiles: makeProfiles(),
    distributions,
  },
});
