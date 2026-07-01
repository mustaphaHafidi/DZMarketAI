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

const textValue = (value: unknown) =>
  typeof value === "string" ? value.trim() : value == null ? "" : String(value);

const normalizeYalidineCredentials = (apiKey: unknown, apiSecret: unknown) => {
  const key = textValue(apiKey);
  const secret = textValue(apiSecret);
  if (!/^\d{1,20}$/.test(key) && /^\d{1,20}$/.test(secret) && key) {
    return { apiKey: secret, apiSecret: key };
  }
  return { apiKey: key, apiSecret: secret };
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

  let payload: { ownerId?: string; courierId?: string };
  try {
    payload = await req.json();
  } catch {
    return new Response(JSON.stringify({ ok: false, message: "Invalid JSON" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const ownerId = (payload.ownerId ?? "").trim();
  const courierId = (payload.courierId ?? "").trim();
  if (!ownerId || !courierId) {
    return new Response(JSON.stringify({ ok: false, message: "Missing parameters" }), {
      status: 400,
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

  const supabaseUser = createClient(url, serviceKey, {
    auth: { persistSession: false },
    global: { headers: { Authorization: auth } },
  });
  const supabaseAdmin = createClient(url, serviceKey, {
    auth: { persistSession: false },
  });

  const { data: userData, error: userError } = await supabaseUser.auth.getUser();
  if (userError || !userData?.user) {
    return new Response(JSON.stringify({ ok: false, message: "Unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
  const userId = userData.user.id;
  if (userId !== ownerId) {
    return new Response(JSON.stringify({ ok: false, message: "Forbidden" }), {
      status: 403,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const ok = await consumeRateLimit(
      supabaseUser,
      `seller_settings:${userId}`,
      30,
      60,
    );
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

  const variants = Array.from(
    new Set([courierId, courierId.toLowerCase(), courierId.toUpperCase()]),
  );

  const { data: healthData, error: healthError } = await supabaseUser
    .from("seller_delivery_settings")
    .select(
      "sender_id, extra, last_validated_at, last_validation_status, last_validation_error, consecutive_failures",
    )
    .eq("owner_id", ownerId)
    .in("courier_id", variants)
    .maybeSingle();

  if (healthError) {
    return new Response(JSON.stringify({ ok: false, message: healthError.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const isEcotrack = variants.includes("ecotrack");
  const { data: secureRows, error: secureError } = await supabaseAdmin.rpc(
    "get_seller_delivery_settings_secure",
    {
      p_owner: ownerId,
      p_courier_id: courierId.toLowerCase(),
    },
  );
  if (secureError) {
    return new Response(JSON.stringify({ ok: false, message: secureError.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
  const secureRow = Array.isArray(secureRows)
    ? secureRows[0]
    : secureRows && typeof secureRows === "object"
    ? secureRows
    : null;

  if (!secureRow || !secureRow.api_key || (!isEcotrack && !secureRow.api_secret)) {
    return new Response(JSON.stringify({ ok: false, message: "Not found" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const normalized = courierId.toLowerCase() === "yalidine"
    ? normalizeYalidineCredentials(secureRow.api_key, secureRow.api_secret)
    : {
      apiKey: textValue(secureRow.api_key),
      apiSecret: textValue(secureRow.api_secret),
    };

  return new Response(
    JSON.stringify({
      ok: true,
      data: {
        api_key: normalized.apiKey,
        api_secret: normalized.apiSecret,
        sender_id: secureRow.sender_id ?? healthData?.sender_id ?? null,
        extra: secureRow.extra ?? healthData?.extra ?? null,
        last_validated_at: healthData?.last_validated_at ?? null,
        last_validation_status: healthData?.last_validation_status ?? null,
        last_validation_error: healthData?.last_validation_error ?? null,
        consecutive_failures: healthData?.consecutive_failures ?? 0,
      },
    }),
    {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    },
  );
});
