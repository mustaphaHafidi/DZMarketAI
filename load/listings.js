import { group } from "k6";
import { cfg, jitter, listProducts, headers } from "./shared.js";
import http from "k6/http";

const vus = Number(__ENV.VUS || 150);
const duration = __ENV.DURATION || "30m";

export const options = {
  vus,
  duration,
  thresholds: {
    http_req_failed: ["rate<0.01"],
    http_req_duration: ["p(95)<350"],
  },
  tags: {
    scenario: "browse-heavy",
  },
};

export default function () {
  group("browse.listings", function () {
    listProducts(24);
    jitter();

    const cheap = http.get(
      `${cfg.baseUrl}/rest/v1/products?select=id,title,price&order=created_at.desc&limit=24&price=lte.5000`,
      headers()
    );
    if (cheap.status >= 400) {
      console.error(`browse cheap failed: ${cheap.status}`);
    }
    jitter();

    const nearby = http.get(
      `${cfg.baseUrl}/rest/v1/products?select=id,title,location_wilaya&order=created_at.desc&limit=24&location_wilaya=not.is.null`,
      headers()
    );
    if (nearby.status >= 400) {
      console.error(`browse nearby failed: ${nearby.status}`);
    }
  });
}
