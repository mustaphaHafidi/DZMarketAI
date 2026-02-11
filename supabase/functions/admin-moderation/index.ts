import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

const textValue = (value: unknown) =>
  typeof value === "string" ? value.trim() : value == null ? "" : String(value);

const errorMessage = (error: unknown) => {
  if (!error) return "";
  if (typeof error === "string") return error;
  if (typeof error === "object") {
    const e = error as Record<string, unknown>;
    return [
      textValue(e["message"]),
      textValue(e["details"]),
      textValue(e["hint"]),
      textValue(e["code"]),
    ]
      .filter((v) => v.length > 0)
      .join(" ")
      .trim();
  }
  return String(error);
};

const missingColumn = (error: unknown) => {
  const message = errorMessage(error).toLowerCase();
  return message.includes("42703") ||
    (message.includes("column") && message.includes("does not exist"));
};

async function updateUserStatus(
  supabaseAdmin: ReturnType<typeof createClient>,
  userId: string,
  status: string,
) {
  const payloads = [{ status }];
  for (const payload of payloads) {
    const { data, error } = await supabaseAdmin
      .from("profiles")
      .update(payload)
      .eq("id", userId)
      .select("id")
      .maybeSingle();
    if (!error) {
      if (!data) throw new Error("user_missing");
      return;
    }
    if (!missingColumn(error)) {
      throw new Error(error.message);
    }
  }
  throw new Error("user_update_failed");
}

async function updateProductModeration(
  supabaseAdmin: ReturnType<typeof createClient>,
  productId: number,
  status: string,
  reason: string | null,
) {
  const blockedFlag = status === "blocked" ? { is_archived: true } : {};
  const now = new Date().toISOString();
  const payloads = [
    {
      moderation_status: status,
      moderation_reason: reason,
      moderation_updated_at: now,
      ...blockedFlag,
    },
    {
      moderation_status: status,
      moderation_reason: reason,
      moderation_updated_at: now,
      ...blockedFlag,
    },
    {
      moderation_status: status,
      moderation_reason: reason,
      ...blockedFlag,
    },
    {
      moderation_status: status,
      ...blockedFlag,
    },
  ];

  for (const payload of payloads) {
    const { data, error } = await supabaseAdmin
      .from("products")
      .update(payload)
      .eq("id", productId)
      .select("id")
      .maybeSingle();
    if (!error) {
      if (!data) throw new Error("product_missing");
      return;
    }
    if (!missingColumn(error)) {
      throw new Error(error.message);
    }
  }
  throw new Error("product_update_failed");
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ ok: false, message: "Method not allowed" }, 405);
  }

  const auth = req.headers.get("authorization") ?? "";
  if (!auth.startsWith("Bearer ")) {
    return jsonResponse({ ok: false, message: "Unauthorized" }, 401);
  }

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !serviceKey) {
    return jsonResponse({ ok: false, message: "Server misconfigured" }, 500);
  }

  const supabaseUser = createClient(url, serviceKey, {
    auth: { persistSession: false },
    global: { headers: { Authorization: auth } },
  });
  const supabaseAdmin = createClient(url, serviceKey, {
    auth: { persistSession: false },
  });

  const { data: userData, error: userError } = await supabaseUser.auth.getUser();
  const actorId = userData?.user?.id;
  if (userError || !actorId) {
    return jsonResponse({ ok: false, message: "Unauthorized" }, 401);
  }

  const { data: actorProfile, error: actorError } = await supabaseAdmin
    .from("profiles")
    .select("role,status")
    .eq("id", actorId)
    .maybeSingle();
  if (actorError || !actorProfile) {
    return jsonResponse({ ok: false, message: "Forbidden" }, 403);
  }
  const role = textValue(actorProfile["role"]).toLowerCase();
  const state = textValue(actorProfile["status"]).toLowerCase();
  if (role !== "superadmin" || (state && state !== "active")) {
    return jsonResponse({ ok: false, message: "Forbidden" }, 403);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ ok: false, message: "Invalid JSON" }, 400);
  }

  const action = textValue(body.action).toLowerCase();
  try {
    if (action === "set_user_status") {
      const userId = textValue(body.user_id);
      const status = textValue(body.status).toLowerCase();
      if (!userId || !["active", "suspended", "banned"].includes(status)) {
        return jsonResponse({ ok: false, message: "Invalid payload" }, 400);
      }
      if (userId === actorId && status !== "active") {
        return jsonResponse(
          { ok: false, message: "self_status_change_forbidden" },
          400,
        );
      }
      await updateUserStatus(supabaseAdmin, userId, status);
      return jsonResponse({ ok: true });
    }

    if (action === "set_product_moderation") {
      const productId = Number(textValue(body.product_id));
      const status = textValue(body.status).toLowerCase();
      const reasonText = textValue(body.reason);
      const reason = reasonText ? reasonText.slice(0, 300) : null;
      if (
        !Number.isFinite(productId) ||
        !["approved", "masked", "blocked"].includes(status)
      ) {
        return jsonResponse({ ok: false, message: "Invalid payload" }, 400);
      }
      await updateProductModeration(supabaseAdmin, productId, status, reason);
      return jsonResponse({ ok: true });
    }

    return jsonResponse({ ok: false, message: "Unknown action" }, 400);
  } catch (error) {
    return jsonResponse(
      { ok: false, message: errorMessage(error) || "Action failed" },
      400,
    );
  }
});
