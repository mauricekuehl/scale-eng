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

// Each API node has its own in-memory cache, and DELETE / clears the DB plus the
// cache of whichever node the load balancer routes the request to. nginx balances
// per request, so repeating the DELETE a few times spreads it across the nodes and
// clears their caches best-effort. Five iterations covers our cluster sizes (<=5).
const TEARDOWN_DELETE_ITERATIONS = 5;

export function teardown() {
  const url = `${requireApiUrl()}/`;
  for (let i = 0; i < TEARDOWN_DELETE_ITERATIONS; i++) {
    http.del(url);
  }
}

export function pickIndex(mode, distribution, size) {
  return config[mode].distributions[distribution].pickIndex(size);
}
