import { check, fail } from "k6";
import http from "k6/http";

import {
  LoadProfile,
  ReadDistribution,
  buildOptions,
  checkCreateResponse,
  pickIndex,
  requireApiUrl,
} from "./common.js";

const API_URL = requireApiUrl();
const PROFILE = __ENV.PROFILE || LoadProfile.STEADY;
const DISTRIBUTION = __ENV.DISTRIBUTION || ReadDistribution.UNIFORM;
const SEED_COUNT = Number.parseInt(__ENV.SEED_COUNT || "1000", 10);

export const options = buildOptions(PROFILE);

export function setup() {
  if (!Number.isFinite(SEED_COUNT) || SEED_COUNT <= 0) {
    fail("SEED_COUNT must be a positive integer");
  }

  const codes = [];
  for (let i = 0; i < SEED_COUNT; i += 1) {
    const url = `https://example.com/load-test/read/${Date.now()}/${i}`;
    const response = http.post(
      `${API_URL}/create`,
      JSON.stringify({ url }),
      {
        headers: { "Content-Type": "application/json" },
      },
    );

    if (!checkCreateResponse(response)) {
      fail(`failed to seed URL ${i}: status ${response.status}`);
    }

    const shortUrl = response.json("shortUrl");
    codes.push(shortUrl.split("/").pop());
  }
  return { codes };
}

export default function (data) {
  const codes = data.codes;
  const index = pickIndex(DISTRIBUTION, codes.length);
  const response = http.get(`${API_URL}/${codes[index]}`, { redirects: 0 });

  check(response, {
    "read returned 302": (res) => res.status === 302,
    "read returned Location": (res) => typeof res.headers.Location === "string",
  });
}
