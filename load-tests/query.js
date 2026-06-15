import http from "k6/http";

import {
  LoadProfile,
  buildOptions,
  checkCreateResponse,
  requireApiUrl,
} from "./common.js";

const API_URL = requireApiUrl();
const PROFILE = __ENV.PROFILE || LoadProfile.STEADY;

export const options = buildOptions(PROFILE);

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
