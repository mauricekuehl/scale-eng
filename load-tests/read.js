import { check, fail } from "k6";
import http from "k6/http";

import {
  checkCreateResponse,
  config,
  getOptions,
  pickIndex,
  requireApiUrl,
} from "./common.js";

const modeConfig = config.read;
const API_URL = requireApiUrl();
const PROFILE = __ENV.PROFILE;
const DISTRIBUTION = __ENV.DISTRIBUTION;
const seedCount = modeConfig.seedCount;

export const options = getOptions("read", PROFILE);

export function setup() {
  if (!Number.isFinite(seedCount) || seedCount <= 0) {
    fail("config.read.seedCount must be a positive integer");
  }

  const codes = [];

  for (let i = 0; i < seedCount; i += modeConfig.seedBatchSize) {
    const batchEnd = Math.min(i + modeConfig.seedBatchSize, seedCount);

    const requests = [];
    for (let j = i; j < batchEnd; j++) {
      const url = `https://example.com/load-test/read/${Date.now()}/${j}`;
      requests.push([
        "POST",
        `${API_URL}/create`,
        JSON.stringify({ url }),
        { headers: { "Content-Type": "application/json" } },
      ]);
    }

    const responses = http.batch(requests);

    for (let k = 0; k < responses.length; k++) {
      if (!checkCreateResponse(responses[k])) {
        fail(`failed to seed URL ${i + k}: status ${responses[k].status}`);
      }
      const shortUrl = responses[k].json("shortUrl");
      codes.push(shortUrl.split("/").pop());
    }
  }

  return { codes };
}

export function teardown() {
  http.del(`${API_URL}/`);
}

export default function (data) {
  const codes = data.codes;
  const index = pickIndex("read", DISTRIBUTION, codes.length);
  const response = http.get(`${API_URL}/${codes[index]}`, { redirects: 0 });

  check(response, {
    "read returned 302": (res) => res.status === 302,
    "read returned Location": (res) => typeof res.headers.Location === "string",
  });
}
