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

async function listAccountDeletionRequests(
  supabaseAdmin: ReturnType<typeof createClient>,
) {
  const { data: requests, error } = await supabaseAdmin
    .from("account_deletion_requests")
    .select(
      "id,user_id,email,reason,status,requested_at,processed_at,updated_at,admin_note,processed_by,account_status_before,account_status_after",
    )
    .order("requested_at", { ascending: false })
    .limit(300);
  if (error) {
    throw new Error(error.message);
  }

  const userIds = Array.from(
    new Set(
      (requests ?? [])
        .flatMap((row) => [textValue(row.user_id), textValue(row.processed_by)])
        .filter((value) => value.length > 0),
    ),
  );

  const profilesById = new Map<string, Record<string, unknown>>();
  if (userIds.length > 0) {
    const { data: profiles, error: profilesError } = await supabaseAdmin
      .from("profiles")
      .select("id,email,full_name,status,role")
      .in("id", userIds);
    if (profilesError) {
      throw new Error(profilesError.message);
    }
    for (const row of profiles ?? []) {
      const id = textValue(row.id);
      if (id) profilesById.set(id, row);
    }
  }

  return (requests ?? []).map((row) => {
    const userId = textValue(row.user_id);
    const processedBy = textValue(row.processed_by);
    return {
      ...row,
      user: userId ? profilesById.get(userId) ?? null : null,
      processed_by_profile: processedBy
        ? profilesById.get(processedBy) ?? null
        : null,
    };
  });
}

async function updateAccountDeletionRequest(
  supabaseAdmin: ReturnType<typeof createClient>,
  actorId: string,
  requestId: number,
  status: string,
  adminNote: string | null,
  userAction: string,
) {
  const allowedStatuses = ["pending", "processing", "completed", "rejected", "cancelled"];
  if (!allowedStatuses.includes(status)) {
    throw new Error("invalid_request_status");
  }

  const { data: requestRow, error: requestError } = await supabaseAdmin
    .from("account_deletion_requests")
    .select("id,user_id,status")
    .eq("id", requestId)
    .maybeSingle();
  if (requestError) throw new Error(requestError.message);
  if (!requestRow) throw new Error("request_missing");

  const userId = textValue(requestRow.user_id);
  if (!userId) throw new Error("request_user_missing");

  const { data: profileRow, error: profileError } = await supabaseAdmin
    .from("profiles")
    .select("id,status")
    .eq("id", userId)
    .maybeSingle();
  if (profileError) throw new Error(profileError.message);
  if (!profileRow) throw new Error("user_missing");

  const accountStatusBefore = textValue(profileRow.status || "active") || "active";
  let accountStatusAfter = accountStatusBefore;

  if (userAction === "suspend" && accountStatusBefore !== "suspended") {
    await updateUserStatus(supabaseAdmin, userId, "suspended");
    accountStatusAfter = "suspended";
  } else if (userAction === "activate" && accountStatusBefore !== "active") {
    await updateUserStatus(supabaseAdmin, userId, "active");
    accountStatusAfter = "active";
  }

  const isTerminal = ["completed", "rejected", "cancelled"].includes(status);
  const payload: Record<string, unknown> = {
    status,
    processed_by: actorId,
    updated_at: new Date().toISOString(),
    account_status_before: accountStatusBefore,
    account_status_after: accountStatusAfter,
    admin_note: adminNote,
    processed_at: isTerminal ? new Date().toISOString() : null,
  };

  const { error: updateError } = await supabaseAdmin
    .from("account_deletion_requests")
    .update(payload)
    .eq("id", requestId);
  if (updateError) throw new Error(updateError.message);
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

    if (action === "list_account_deletion_requests") {
      const requests = await listAccountDeletionRequests(supabaseAdmin);
      return jsonResponse({ ok: true, requests });
    }

    if (action === "set_account_deletion_request_status") {
      const requestId = Number(textValue(body.request_id));
      const status = textValue(body.status).toLowerCase();
      const adminNoteRaw = textValue(body.admin_note);
      const adminNote = adminNoteRaw ? adminNoteRaw.slice(0, 500) : null;
      const userAction = textValue(body.user_action).toLowerCase() || "none";
      if (!Number.isFinite(requestId) || !status) {
        return jsonResponse({ ok: false, message: "Invalid payload" }, 400);
      }
      if (!["none", "suspend", "activate"].includes(userAction)) {
        return jsonResponse({ ok: false, message: "Invalid payload" }, 400);
      }
      await updateAccountDeletionRequest(
        supabaseAdmin,
        actorId,
        requestId,
        status,
        adminNote,
        userAction,
      );
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
