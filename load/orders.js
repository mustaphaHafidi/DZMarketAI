import http from "k6/http";
import { cfg, authHeaders, healthPing, maybeSkip, pass, jitter } from "./shared.js";

const vus = Number(__ENV.VUS || 60);
const duration = __ENV.DURATION || "30m";
const writesEnabled = __ENV.WRITE_ENABLED === "1";
const testProductId = __ENV.TEST_PRODUCT_ID || "";
const offerAmount = __ENV.TEST_OFFER_AMOUNT || "1000";

export const options = {
  vus,
  duration,
  thresholds: {
    http_req_failed: ["rate<0.01"],
    http_req_duration: ["p(95)<500"],
  },
  tags: {
    scenario: "commerce-write-path",
  },
};

export default function () {
  if (maybeSkip(!cfg.buyerJwt, "missing_buyer_jwt")) {
    healthPing("orders.health_fallback");
    return;
  }

  const listOrders = http.get(
    `${cfg.baseUrl}/rest/v1/orders?select=id,status,created_at&order=created_at.desc&limit=20`,
    authHeaders(cfg.buyerJwt)
  );
  pass(listOrders, "orders.list");
  jitter();

  if (!writesEnabled) {
    return;
  }

  if (maybeSkip(!testProductId, "missing_test_product_id")) {
    return;
  }

  const createOffer = http.post(
    `${cfg.baseUrl}/rest/v1/offers`,
    JSON.stringify({
      product_id: Number(testProductId),
      amount: Number(offerAmount),
      message: "k6-load-offer",
    }),
    authHeaders(cfg.buyerJwt)
  );
  pass(createOffer, "orders.create_offer");
}

