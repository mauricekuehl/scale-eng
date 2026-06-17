import http from "k6/http";

import {
  checkCreateResponse,
  getOptions,
  requireApiUrl,
  teardown as teardownApi,
} from "./common.js";

const API_URL = requireApiUrl();
const PROFILE = __ENV.PROFILE;

export const options = getOptions("query", PROFILE);

export function teardown() {
  teardownApi();
}

export default function () {
  const url = `https://example.com/load-test/query/${__VU}/${__ITER}/${Date.now()}`;
  const response = http.post(
    `${API_URL}/create`,
    JSON.stringify({ url }),
    {
      headers: { "Content-Type": "application/json" },
    },
  );

  checkCreateResponse(response);
}
