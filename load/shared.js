import http from "k6/http";
import { check, sleep } from "k6";
import { Counter } from "k6/metrics";

export const skipped = new Counter("dzmarket_skipped_ops");

export const cfg = {
  baseUrl: __ENV.BASE_URL || "https://api.dzmarket.pro",
  appUrl: __ENV.APP_URL || "https://app.dzmarket.pro",
  anonKey: __ENV.ANON_KEY || "",
  buyerJwt: __ENV.TEST_BUYER_JWT || "",
  sellerJwt: __ENV.TEST_SELLER_JWT || "",
  testOrderId: __ENV.TEST_ORDER_ID || "",
  testLabelUrl: __ENV.TEST_LABEL_URL || "",
};

export function headers(extra = {}) {
  const h = {
    "Content-Type": "application/json",
  };
  if (cfg.anonKey) {
    h.apikey = cfg.anonKey;
  }
  return { headers: { ...h, ...extra } };
}

export function authHeaders(jwt) {
  if (!jwt) {
    return headers();
  }
  return headers({ Authorization: `Bearer ${jwt}` });
}

export function pass(res, name) {
  const ok = check(res, {
    [`${name} status ok`]: (r) => r.status >= 200 && r.status < 400,
  });
  if (!ok) {
    console.error(`${name} failed: status=${res.status} body=${String(res.body).slice(0, 300)}`);
  }
}

export function maybeSkip(condition, reason) {
  if (condition) {
    skipped.add(1, { reason });
    return true;
  }
  return false;
}

export function jitter() {
  sleep(Math.random() * 0.8 + 0.2);
}

export function healthPing(tag = "health") {
  const res = http.get(`${cfg.baseUrl}/auth/v1/health`, headers());
  pass(res, tag);
  return res;
}

export function listProducts(limit = 24) {
  const query = `/rest/v1/products?select=id,title,price,stock_quantity,created_at&order=created_at.desc&limit=${limit}`;
  const res = http.get(`${cfg.baseUrl}${query}`, headers());
  pass(res, "list_products");
  return res;
}
