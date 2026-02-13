import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const consumeRateLimit = async (
  supabase: ReturnType<typeof createClient>,
  key: string,
  limit: number,
  windowSeconds: number,
) => {
  const { data, error } = await supabase.rpc("consume_rate_limit", {
    p_key: key,
    p_limit: limit,
    p_window_seconds: windowSeconds,
  });
  if (error) throw new Error(error.message);
  return data === true;
};

const sleep = (ms: number) =>
  new Promise((resolve) => setTimeout(resolve, ms));

const parseRetryAfterMs = (value: string | null) => {
  if (!value) return null;
  const seconds = Number(value);
  if (Number.isFinite(seconds) && seconds > 0) return Math.min(seconds * 1000, 15000);
  const dateMs = Date.parse(value);
  if (Number.isFinite(dateMs)) {
    const delta = dateMs - Date.now();
    if (delta > 0) return Math.min(delta, 15000);
  }
  return null;
};

const isRetryableStatus = (status: number) =>
  status === 408 || status === 429 || status >= 500;

const fetchWithRetry = async (
  url: string,
  init: RequestInit,
  maxAttempts = 4,
) => {
  let lastError: unknown = null;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const resp = await fetch(url, init);
      if (!isRetryableStatus(resp.status) || attempt === maxAttempts) return resp;
      const retryAfterMs = parseRetryAfterMs(resp.headers.get("Retry-After"));
      const jitter = Math.floor(Math.random() * 120);
      const backoff = Math.min(300 * 2 ** (attempt - 1), 4000);
      await sleep((retryAfterMs ?? backoff) + jitter);
    } catch (error) {
      lastError = error;
      if (attempt === maxAttempts) break;
      const jitter = Math.floor(Math.random() * 120);
      const backoff = Math.min(300 * 2 ** (attempt - 1), 4000);
      await sleep(backoff + jitter);
    }
  }
  throw lastError instanceof Error ? lastError : new Error("network_retry_failed");
};

type CarrierRateWindow = { limit: number; seconds: number };

const probeRatePolicy = (carrierCode: string): CarrierRateWindow[] => {
  switch (carrierCode) {
    case "guepex":
      return [{ limit: 4, seconds: 1 }, { limit: 40, seconds: 60 }];
    case "ecotrack":
      return [{ limit: 45, seconds: 60 }];
    case "yalidine":
      return [{ limit: 8, seconds: 1 }, { limit: 80, seconds: 60 }];
    case "zrexpress":
      return [{ limit: 8, seconds: 1 }, { limit: 80, seconds: 60 }];
    default:
      return [{ limit: 10, seconds: 60 }];
  }
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ ok: false, message: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const auth = req.headers.get("authorization") ?? "";
  if (!auth.startsWith("Bearer ")) {
    return new Response(JSON.stringify({ ok: false, message: "Unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !serviceKey) {
    return new Response(JSON.stringify({ ok: false, message: "Server misconfigured" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
  const supabase = createClient(url, serviceKey, {
    auth: { persistSession: false },
    global: { headers: { Authorization: auth } },
  });
  try {
    const { data: userData } = await supabase.auth.getUser();
    const userId = userData?.user?.id ?? "anon";
    const ok = await consumeRateLimit(supabase, `courier:${userId}`, 20, 60);
    if (!ok) {
      return new Response(
        JSON.stringify({ ok: false, message: "Rate limit exceeded" }),
        { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
  } catch {
    return new Response(JSON.stringify({ ok: false, message: "Rate limit error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  let payload: { courierName?: string; apiKey?: string; apiSecret?: string };
  try {
    payload = await req.json();
  } catch {
    return new Response(JSON.stringify({ ok: false, message: "Invalid JSON" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const courierName = (payload.courierName ?? "").trim().toLowerCase();
  const apiKey = (payload.apiKey ?? "").trim();
  const apiSecret = (payload.apiSecret ?? "").trim();
  if (!courierName || !apiKey || (!apiSecret && !courierName.includes("ecotrack"))) {
    return new Response(
      JSON.stringify({ ok: false, message: "Missing credentials" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const courierCode = courierName.includes("yalidine")
    ? "yalidine"
    : courierName.includes("ecotrack")
    ? "ecotrack"
    : (courierName.includes("zrexpress") ||
        courierName.includes("zr express") ||
        courierName.includes("zr-express"))
    ? "zrexpress"
    : courierName.includes("guepex")
    ? "guepex"
    : "generic";

  try {
    for (const window of probeRatePolicy(courierCode)) {
      const ok = await consumeRateLimit(
        supabase,
        `courier_probe:${courierCode}:${window.seconds}`,
        window.limit,
        window.seconds,
      );
      if (!ok) {
        return new Response(
          JSON.stringify({ ok: false, message: "courier_rate_limited" }),
          { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
    }
  } catch {
    return new Response(
      JSON.stringify({ ok: false, message: "Rate limit error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  if (courierName.includes("yalidine")) {
    const url = "https://api.yalidine.app/v1/wilayas/";
    const headers = {
      "X-API-ID": apiKey,
      "X-API-TOKEN": apiSecret,
      Accept: "application/json",
    };
    const resp = await fetchWithRetry(url, { method: "GET", headers });
    if (resp.status === 200) {
      return new Response(JSON.stringify({ ok: true, message: "OK" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const swapHeaders = {
      "X-API-ID": apiSecret,
      "X-API-TOKEN": apiKey,
      Accept: "application/json",
    };
    const respSwap = await fetchWithRetry(
      url,
      { method: "GET", headers: swapHeaders },
    );
    if (respSwap.status === 200) {
      return new Response(JSON.stringify({ ok: true, message: "OK" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    return new Response(
      JSON.stringify({ ok: false, message: "Token invalide" }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  if (courierName.includes("ecotrack")) {
    const urlWithParam = `https://api.ecotrack.dz/api/v1/validate/token?api_token=${encodeURIComponent(apiKey)}`;
    const urlNoParam = "https://api.ecotrack.dz/api/v1/validate/token";
    const headers = {
      Authorization: `Bearer ${apiKey}`,
      Accept: "application/json",
    };
    const attempt = async (url: string) => {
      const resp = await fetchWithRetry(url, { method: "GET", headers });
      const bodyText = await resp.text();
      let message = "";
      try {
        const parsed = JSON.parse(bodyText);
        if (parsed && typeof parsed.message === "string") {
          message = parsed.message;
        }
      } catch {
        message = bodyText.trim();
      }
      const invalidMessages = ["INVALID_TOKEN", "TOKEN_NOT_ALLOWED"];
      const okMessage = message === "" || !invalidMessages.includes(message);
      return { resp, message, okMessage };
    };

    const first = await attempt(urlWithParam);
    if (first.resp.status === 200 && first.okMessage) {
      return new Response(JSON.stringify({ ok: true, message: "OK" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const second = await attempt(urlNoParam);
    if (second.resp.status === 200 && second.okMessage) {
      return new Response(JSON.stringify({ ok: true, message: "OK" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const finalMessage = second.message || first.message || "Token invalide";
    return new Response(
      JSON.stringify({ ok: false, message: finalMessage }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  if (courierName.includes("zrexpress") ||
      courierName.includes("zr express") ||
      courierName.includes("zr-express")) {
    const url = "https://api.zrexpress.app/api/v1/users/profile";
    const headers = {
      "X-Api-Key": apiKey,
      "X-Tenant": apiSecret,
      Accept: "application/json",
    };
    const resp = await fetchWithRetry(url, { method: "GET", headers });
    if (resp.ok) {
      return new Response(JSON.stringify({ ok: true, message: "OK" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const bodyText = await resp.text();
    let message = bodyText.trim();
    try {
      const parsed = JSON.parse(bodyText);
      if (parsed && typeof parsed.message === "string") {
        message = parsed.message;
      }
    } catch {
      // keep raw text
    }
    return new Response(
      JSON.stringify({ ok: false, message: message || "Token invalide" }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  if (courierName.includes("guepex")) {
    const baseUrl = (Deno.env.get("GUEPEX_BASE_URL") ?? "https://api.guepex.app")
      .trim()
      .replace(/\/+$/, "");
    const url = `${baseUrl}/v1/wilayas`;
    const headers = {
      "X-API-ID": apiKey,
      "X-API-TOKEN": apiSecret,
      Accept: "application/json",
    };
    const resp = await fetchWithRetry(url, { method: "GET", headers });
    if (resp.ok) {
      return new Response(JSON.stringify({ ok: true, message: "OK" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const bodyText = await resp.text();
    let message = bodyText.trim();
    try {
      const parsed = JSON.parse(bodyText);
      if (parsed && typeof parsed.message === "string") {
        message = parsed.message;
      }
    } catch {
      // keep raw text
    }
    return new Response(
      JSON.stringify({ ok: false, message: message || "Token invalide" }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  return new Response(
    JSON.stringify({ ok: false, message: "Validation non supportee" }),
    { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});
