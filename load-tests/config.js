export const config = Object.freeze({
  query: {
    profiles: {
      steady: {
        scenarios: {
          steady: {
            executor: "constant-vus",
            vus: 20,
            duration: "2m",
          },
        },
        thresholds: {
          http_req_failed: [
            {
              threshold: "rate<0.05",
              abortOnFail: false,
              delayAbortEval: "30s",
            },
          ],
          http_req_duration: [
            {
              threshold: "p(95)<2000",
              abortOnFail: false,
              delayAbortEval: "30s",
            },
          ],
        },
      },
      spike: {
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
        thresholds: {
          http_req_failed: [
            {
              threshold: "rate<0.05",
              abortOnFail: false,
              delayAbortEval: "30s",
            },
          ],
          http_req_duration: [
            {
              threshold: "p(95)<2000",
              abortOnFail: false,
              delayAbortEval: "30s",
            },
          ],
        },
      },
      breakpoint: {
        scenarios: {
          breakpoint: {
            executor: "ramping-arrival-rate",
            timeUnit: "1s",
            preAllocatedVUs: 50,
            maxVUs: 500,
            stages: [
              { duration: "1m", target: 10 },
              { duration: "2m", target: 50 },
              { duration: "2m", target: 100 },
              { duration: "2m", target: 200 },
              { duration: "2m", target: 300 },
              { duration: "1m", target: 0 },
            ],
          },
        },
        thresholds: {
          http_req_failed: [
            {
              threshold: "rate<0.05",
              abortOnFail: true,
              delayAbortEval: "30s",
            },
          ],
          http_req_duration: [
            {
              threshold: "p(95)<2000",
              abortOnFail: true,
              delayAbortEval: "30s",
            },
          ],
          dropped_iterations: [
            {
              threshold: "count<1",
              abortOnFail: true,
              delayAbortEval: "30s",
            },
          ],
        },
      },
    },
  },
  read: {
    seedCount: 1000,
    seedBatchSize: 50,
    profiles: {
      steady: {
        scenarios: {
          steady: {
            executor: "constant-vus",
            vus: 20,
            duration: "2m",
          },
        },
        thresholds: {
          http_req_failed: [
            {
              threshold: "rate<0.05",
              abortOnFail: false,
              delayAbortEval: "30s",
            },
          ],
          http_req_duration: [
            {
              threshold: "p(95)<2000",
              abortOnFail: false,
              delayAbortEval: "30s",
            },
          ],
        },
      },
      spike: {
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
        thresholds: {
          http_req_failed: [
            {
              threshold: "rate<0.05",
              abortOnFail: false,
              delayAbortEval: "30s",
            },
          ],
          http_req_duration: [
            {
              threshold: "p(95)<2000",
              abortOnFail: false,
              delayAbortEval: "30s",
            },
          ],
        },
      },
      breakpoint: {
        scenarios: {
          breakpoint: {
            executor: "ramping-arrival-rate",
            timeUnit: "1s",
            preAllocatedVUs: 50,
            maxVUs: 500,
            stages: [
              { duration: "1m", target: 10 },
              { duration: "2m", target: 50 },
              { duration: "2m", target: 100 },
              { duration: "2m", target: 200 },
              { duration: "2m", target: 300 },
              { duration: "1m", target: 0 },
            ],
          },
        },
        thresholds: {
          http_req_failed: [
            {
              threshold: "rate<0.05",
              abortOnFail: true,
              delayAbortEval: "30s",
            },
          ],
          http_req_duration: [
            {
              threshold: "p(95)<2000",
              abortOnFail: true,
              delayAbortEval: "30s",
            },
          ],
          dropped_iterations: [
            {
              threshold: "count<1",
              abortOnFail: true,
              delayAbortEval: "30s",
            },
          ],
        },
      },
    },
    distributions: {
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
    },
  },
});
