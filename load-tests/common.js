import { check } from "k6";
import http from "k6/http";

import { config } from "./config.js";

export function requireApiUrl() {
  return __ENV.API_URL.replace(/\/+$/, "");
}

export function getOptions(mode, profile) {
  return config[mode].profiles[profile];
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

export function teardown() {
  http.del(`${requireApiUrl()}/`);
}

export function pickIndex(mode, distribution, size) {
  return config[mode].distributions[distribution].pickIndex(size);
}
