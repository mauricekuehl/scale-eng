import { check, fail } from "k6";
import http from "k6/http";

import {
  checkCreateResponse,
  config,
  getOptions,
  pickIndex,
  requireApiUrl,
} from "./common.js";

const readConfig = config.read;
const API_URL = requireApiUrl();
const PROFILE = __ENV.PROFILE;
const DISTRIBUTION = __ENV.DISTRIBUTION;
const seedCount = readConfig.seedCount;
const READ_RATIO = 0.9;

export const options = getOptions("query", PROFILE);

export function setup() {
  if (!Number.isFinite(seedCount) || seedCount <= 0) {
    fail("config.read.seedCount must be a positive integer");
  }

  const codes = [];

  for (let i = 0; i < seedCount; i += readConfig.seedBatchSize) {
    const batchEnd = Math.min(i + readConfig.seedBatchSize, seedCount);

    const requests = [];
    for (let j = i; j < batchEnd; j++) {
      const url = `https://example.com/load-test/mixed/${Date.now()}/${j}`;
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
      codes.push(responses[k].json("shortUrl").split("/").pop());
    }
  }

  return { codes };
}

export function teardown() {
  http.del(`${API_URL}/`);
}

export default function (data) {
  if (Math.random() < READ_RATIO) {
    const index = pickIndex("read", DISTRIBUTION, data.codes.length);
    const response = http.get(`${API_URL}/${data.codes[index]}`, { redirects: 0 });
    check(response, {
      "read returned 302": (res) => res.status === 302,
      "read returned Location": (res) => typeof res.headers.Location === "string",
    });
  } else {
    const url = `https://example.com/load-test/mixed/write/${__VU}/${__ITER}/${Date.now()}`;
    const response = http.post(
      `${API_URL}/create`,
      JSON.stringify({ url }),
      { headers: { "Content-Type": "application/json" } },
    );
    checkCreateResponse(response);
  }
}
