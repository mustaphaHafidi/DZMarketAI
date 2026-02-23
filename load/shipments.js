import http from "k6/http";
import { cfg, authHeaders, maybeSkip, pass, healthPing, jitter } from "./shared.js";

const vus = Number(__ENV.VUS || 40);
const duration = __ENV.DURATION || "30m";
const generateEnabled = __ENV.ENABLE_GENERATE_SHIPMENT === "1";

export const options = {
  vus,
  duration,
  thresholds: {
    http_req_failed: ["rate<0.01"],
    http_req_duration: ["p(95)<700"],
  },
  tags: {
    scenario: "shipment-label",
  },
};

export default function () {
  if (maybeSkip(!cfg.sellerJwt, "missing_seller_jwt")) {
    healthPing("shipments.health_fallback");
    return;
  }

  const list = http.get(
    `${cfg.baseUrl}/rest/v1/shipments?select=id,order_id,label_url,created_at&order=created_at.desc&limit=20`,
    authHeaders(cfg.sellerJwt)
  );
  pass(list, "shipments.list");
  jitter();

  if (!maybeSkip(!cfg.testLabelUrl, "missing_test_label_url")) {
    const labelRes = http.get(cfg.testLabelUrl, { redirects: 0 });
    pass(labelRes, "shipments.open_label");
  }

  if (!generateEnabled) {
    return;
  }

  if (maybeSkip(!cfg.testOrderId, "missing_test_order_id")) {
    return;
  }

  const gen = http.post(
    `${cfg.baseUrl}/functions/v1/create_shipment`,
    JSON.stringify({ order_id: Number(cfg.testOrderId) }),
    authHeaders(cfg.sellerJwt)
  );
  pass(gen, "shipments.generate");
}

