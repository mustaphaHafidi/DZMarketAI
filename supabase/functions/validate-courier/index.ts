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

  if (courierName.includes("yalidine")) {
    const url = "https://api.yalidine.app/v1/wilayas/";
    const headers = {
      "X-API-ID": apiKey,
      "X-API-TOKEN": apiSecret,
      Accept: "application/json",
    };
    const resp = await fetch(url, { headers });
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
    const respSwap = await fetch(url, { headers: swapHeaders });
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
      const resp = await fetch(url, { headers });
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

  return new Response(
    JSON.stringify({ ok: false, message: "Validation non supportee" }),
    { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});
