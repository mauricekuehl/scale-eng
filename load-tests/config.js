// Central tuning surface for all load tests.
//
// The headline metric is "maximum sustained throughput while the SLO holds".
// The breakpoint profile ramps an open-model arrival rate upward until the SLO
// is breached, so a faster system (e.g. after sharding the DB) reaches a higher
// rate before aborting. Calibrate the breakpoint max rate against your *strongest*
// configuration once, then keep it fixed so every config is comparable.
//
function sloThresholds(abortOnFail) {
  return {
    http_req_failed: [
      { threshold: "rate<0.01", abortOnFail, delayAbortEval: "30s" },
    ],
    http_req_duration: [
      { threshold: "p(95)<500", abortOnFail, delayAbortEval: "30s" },
    ],
  };
}


function makeProfiles() {
  return {
    steady: {
      setupTimeout: "5m",
      scenarios: {
        steady: {
          executor: "constant-vus",
          vus: 20,
          duration: "2m",
        },
      },
      thresholds: sloThresholds(false),
    },
    spike: {
      setupTimeout: "5m",
      scenarios: {
        spike: {
          executor: "ramping-vus",
          stages: [
            { duration: "15s", target: 20 },
            { duration: "30s", target: 100 },
            { duration: "1m", target: 100 },
            { duration: "30s", target: 0 },
          ],
        },
      },
      thresholds: sloThresholds(false),
    },
    breakpoint: {
      setupTimeout: "5m",
      scenarios: {
        breakpoint: {
          executor: "ramping-arrival-rate",
          timeUnit: "1s",
          startRate: 25,
          preAllocatedVUs: 200,
          maxVUs: 10000,
          stages: [{ duration: "10m", target: 1000 }],
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
      const alpha = 1.2;
      const p = Math.random();

      const a = 1 - alpha;

      const x = Math.pow(
        1 + p * (Math.pow(size, a) - 1),
        1 / a
      );

      return Math.floor(x) - 1;
    },
  },
};

export const config = Object.freeze({
  query: {
    profiles: makeProfiles(),
  },
  read: {
    seedCount: 10000,
    seedBatchSize: 100,
    profiles: makeProfiles(),
    distributions,
  },
  mixed: {
    seedCount: 10000,
    seedBatchSize: 100,
    profiles: makeProfiles(),
    distributions,
  },
});
