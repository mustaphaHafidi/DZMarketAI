import http from "k6/http";
import { cfg, headers, pass, jitter, maybeSkip, healthPing } from "./shared.js";

const vus = Number(__ENV.VUS || 80);
const duration = __ENV.DURATION || "30m";
const recoveryEnabled = __ENV.ENABLE_RECOVERY === "1";
const recoveryEmail = __ENV.RECOVERY_EMAIL || "";
const testEmail = __ENV.TEST_EMAIL || "";
const testPassword = __ENV.TEST_PASSWORD || "";
const authTestMode = (__ENV.AUTH_TEST_MODE || "single").toLowerCase();
const authP95Ms = Number(__ENV.AUTH_P95_MS || 300);
const testUsersJson = __ENV.TEST_USERS_JSON || "";

function parseUsersPool(raw) {
  if (!raw) return [];
  try {
    const arr = JSON.parse(raw);
    if (!Array.isArray(arr)) return [];
    return arr
      .filter((u) => u && typeof u.email === "string" && typeof u.password === "string")
      .map((u) => ({ email: u.email.trim(), password: u.password }))
      .filter((u) => u.email.length > 0 && u.password.length > 0);
  } catch (_) {
    return [];
  }
}

const usersPool = parseUsersPool(testUsersJson);

function currentCredentials() {
  if (authTestMode === "pool" && usersPool.length > 0) {
    const idx = (__VU - 1) % usersPool.length;
    return usersPool[idx];
  }
  return { email: testEmail, password: testPassword };
}

export const options = {
  vus,
  duration,
  thresholds: {
    http_req_failed: ["rate<0.01"],
    http_req_duration: [`p(95)<${authP95Ms}`],
  },
  tags: {
    scenario: "auth-burst",
  },
};

export default function () {
  healthPing("auth.health");
  jitter();

  const hasSingleCreds = !!testEmail && !!testPassword;
  if (
    authTestMode === "pool" &&
    usersPool.length === 0 &&
    maybeSkip(!hasSingleCreds, "missing_test_users_pool")
  ) {
    return;
  }

  const creds = currentCredentials();
  if (!maybeSkip(!creds.email || !creds.password, "missing_test_credentials")) {
    const loginRes = http.post(
      `${cfg.baseUrl}/auth/v1/token?grant_type=password`,
      JSON.stringify({
        email: creds.email,
        password: creds.password,
      }),
      headers()
    );
    pass(loginRes, "auth.login_password");
  }

  if (recoveryEnabled) {
    if (maybeSkip(!recoveryEmail, "missing_recovery_email")) {
      return;
    }
    const recoverRes = http.post(
      `${cfg.baseUrl}/auth/v1/recover`,
      JSON.stringify({ email: recoveryEmail }),
      headers()
    );
    pass(recoverRes, "auth.recovery");
  }
}
