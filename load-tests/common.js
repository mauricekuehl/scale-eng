import { check } from "k6";

export const LoadProfile = Object.freeze({
  STEADY: "steady",
  SPIKE: "spike",
  BREAKPOINT: "breakpoint",
});

export const ReadDistribution = Object.freeze({
  CONSTANT: "constant",
  UNIFORM: "uniform",
  HOTSPOT: "hotspot",
});

export function requireApiUrl() {
  const apiUrl = __ENV.API_URL;
  if (!apiUrl) {
    throw new Error("API_URL is required");
  }
  return apiUrl.replace(/\/+$/, "");
}

export function buildOptions(profile) {
  const thresholds = {
    http_req_failed: [
      {
        threshold: "rate<0.05",
        abortOnFail: profile === LoadProfile.BREAKPOINT,
        delayAbortEval: "30s",
      },
    ],
    http_req_duration: [
      {
        threshold: "p(95)<2000",
        abortOnFail: profile === LoadProfile.BREAKPOINT,
        delayAbortEval: "30s",
      },
    ],
  };

  if (profile === LoadProfile.BREAKPOINT) {
    thresholds.dropped_iterations = [
      {
        threshold: "count<1",
        abortOnFail: true,
        delayAbortEval: "30s",
      },
    ];
  }

  if (profile === LoadProfile.STEADY) {
    return {
      scenarios: {
        steady: {
          executor: "constant-vus",
          vus: 20,
          duration: "2m",
        },
      },
      thresholds,
    };
  }

  if (profile === LoadProfile.SPIKE) {
    return {
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
      thresholds,
    };
  }

  if (profile === LoadProfile.BREAKPOINT) {
    return {
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
      thresholds,
    };
  }

  throw new Error(`unknown PROFILE: ${profile}`);
}

export function checkCreateResponse(response) {
  return check(response, {
    "create returned 201": (res) => res.status === 201,
    "create returned a shortUrl": (res) => {
      try {
        return typeof res.json("shortUrl") === "string";
      } catch {
        return false;
      }
    },
  });
}

export function pickIndex(distribution, size) {
  if (size <= 0) {
    throw new Error("cannot pick from an empty set");
  }

  if (distribution === ReadDistribution.CONSTANT) {
    return 0;
  }

  if (distribution === ReadDistribution.UNIFORM) {
    return Math.floor(Math.random() * size);
  }

  if (distribution === ReadDistribution.HOTSPOT) {
    if (Math.random() < 0.8) {
      return Math.floor(Math.random() * (size * 0.2));
    }
    return Math.floor(Math.random() * size);
  }

  throw new Error(`unknown DISTRIBUTION: ${distribution}`);
}
