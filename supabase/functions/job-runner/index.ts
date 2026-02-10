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

const normalizeCourier = (value: string) =>
  value.toLowerCase().replace(/[^a-z0-9]/g, "");

const returnMarkers = [
  "retour",
  "retourn",
  "returned",
  "return to sender",
  "non reclam",
  "non réclam",
  "not claimed",
  "rts",
  "refus",
];

const ecotrackReturnMarkers = [
  "return_in_transit",
  "return received",
  "return_received",
  "returnreceived",
];

const flattenValues = (value: unknown, out: string[]) => {
  if (typeof value === "string") {
    out.push(value);
    return;
  }
  if (Array.isArray(value)) {
    for (const item of value) flattenValues(item, out);
    return;
  }
  if (value && typeof value === "object") {
    for (const val of Object.values(value as Record<string, unknown>)) {
      flattenValues(val, out);
    }
  }
};

const flattenKeys = (value: unknown, out: string[]) => {
  if (Array.isArray(value)) {
    for (const item of value) flattenKeys(item, out);
    return;
  }
  if (value && typeof value === "object") {
    for (const [key, val] of Object.entries(value as Record<string, unknown>)) {
      out.push(key);
      flattenKeys(val, out);
    }
  }
};

const detectReturnFromText = (text: string) => {
  const lower = text.toLowerCase();
  if (lower.includes("non reclam") || lower.includes("not claimed")) return "not_claimed";
  if (lower.includes("refus")) return "refused";
  if (
    lower.includes("return_in_transit") ||
    lower.includes("return_received") ||
    lower.includes("return received") ||
    lower.includes("return to sender") ||
    lower.includes("rts") ||
    lower.includes("retour")
  ) {
    return "returned_to_sender";
  }
  return null;
};

const detectReturn = (data: unknown) => {
  try {
    const parts: string[] = [];
    flattenValues(data, parts);
    if (parts.length === 0) return null;
    const text = parts.join(" ").toLowerCase();
    const found = returnMarkers.find((marker) => text.includes(marker));
    if (!found) return null;
    return detectReturnFromText(found) ?? "returned_to_sender";
  } catch {
    return null;
  }
};

const detectEcotrackReturn = (data: unknown) => {
  const parts: string[] = [];
  flattenValues(data, parts);
  const joined = parts.join(" ").toLowerCase();
  const found = ecotrackReturnMarkers.find((marker) => joined.includes(marker));
  if (found) return "returned_to_sender";
  return detectReturnFromText(joined);
};

const detectZrExpressReturn = (data: unknown) => {
  if (!data || typeof data !== "object") return null;
  const keyParts: string[] = [];
  flattenKeys(data, keyParts);
  const keyJoined = keyParts.join(" ").toLowerCase();
  if (keyJoined.includes("isreturn") || keyJoined.includes("returnstatus")) {
    return "returned_to_sender";
  }
  const valueParts: string[] = [];
  flattenValues(data, valueParts);
  const joined = valueParts.join(" ").toLowerCase();
  return detectReturnFromText(joined);
};

const detectTrackingStatusFromText = (text: string) => {
  const lower = text.toLowerCase();
  const returnStatus = detectReturnFromText(lower);
  if (returnStatus) return returnStatus;

  if (
    lower.includes("livred") ||
    lower.includes("delivered") ||
    lower.includes("livre") ||
    lower.includes("encaissed") ||
    lower.includes("payed")
  ) {
    return "delivered";
  }

  if (
    lower.includes("picked") ||
    lower.includes("accepted_by_carrier") ||
    lower.includes("dispatched_to_driver") ||
    lower.includes("attempt_delivery") ||
    lower.includes("in_transit") ||
    lower.includes("expedie") ||
    lower.includes("shipped")
  ) {
    return "shipped";
  }

  if (lower.includes("validated") || lower.includes("validation")) {
    return "validated";
  }

  return null;
};

const detectTrackingStatus = (data: unknown) => {
  const parts: string[] = [];
  flattenValues(data, parts);
  if (parts.length === 0) return null;
  const joined = parts.join(" ");
  return detectTrackingStatusFromText(joined);
};
const fetchJson = async (url: string, headers: HeadersInit) => {
  const resp = await fetch(url, { headers });
  if (!resp.ok) return null;
  try {
    return await resp.json();
  } catch {
    return null;
  }
};

const ecotrackBaseUrls = () => {
  const envValue = (Deno.env.get("ECOTRACK_BASE_URL") ?? "").trim();
  const candidates = [envValue, "https://api.ecotrack.dz", "https://ovred.ecotrack.dz"];
  const seen = new Set<string>();
  return candidates.filter((v) => {
    const normalized = v.replace(/\/+$/, "");
    if (!normalized || seen.has(normalized)) return false;
    seen.add(normalized);
    return true;
  });
};

const syncBuyerReturns = async (supabase: ReturnType<typeof createClient>) => {
  const since = new Date();
  since.setMonth(since.getMonth() - 12);
  const { data: existingEvents } = await supabase
    .from("buyer_return_events")
    .select("order_id");
  const existingOrders = new Set(
    (existingEvents ?? []).map((row) => row.order_id?.toString()).filter(Boolean),
  );

  const { data: orders } = await supabase
    .from("orders")
    .select("id,buyer_id,seller_id,courier_id,courier_name,tracking_number,created_at")
    .not("tracking_number", "is", null)
    .gte("created_at", since.toISOString())
    .order("created_at", { ascending: false })
    .limit(40);

  const orderList = Array.isArray(orders) ? orders : [];
  const pending = orderList.filter(
    (order) => order?.tracking_number && !existingOrders.has(order.id?.toString()),
  );
  if (pending.length === 0) return 0;

  const sellerIds = Array.from(
    new Set(pending.map((order) => order.seller_id).filter(Boolean)),
  );
  const courierIds = Array.from(
    new Set(pending.map((order) => order.courier_id).filter(Boolean)),
  );

  const { data: settings } = await supabase
    .from("seller_delivery_settings")
    .select("owner_id,courier_id,api_key,api_secret")
    .in("owner_id", sellerIds)
    .in("courier_id", courierIds);

  const settingsMap = new Map<string, { api_key: string; api_secret: string }>();
  for (const row of settings ?? []) {
    if (!row?.owner_id || !row?.courier_id || !row?.api_key) continue;
    settingsMap.set(`${row.owner_id}:${row.courier_id}`, {
      api_key: row.api_key,
      api_secret: row.api_secret ?? "",
    });
  }

  let inserted = 0;
  for (const order of pending) {
    const courierId = order.courier_id ?? "";
    const courierName = order.courier_name ?? "";
    const normalized = normalizeCourier(`${courierId} ${courierName}`);
    const settings =
      settingsMap.get(`${order.seller_id}:${courierId}`) ??
      settingsMap.get(`${order.seller_id}:${order.courier_id}`) ??
      null;
    if (!settings) continue;

    const tracking = order.tracking_number?.toString() ?? "";
    if (!tracking) continue;

    let trackingData: unknown = null;
    if (normalized.includes("yalidine")) {
      trackingData = await fetchJson(
        `https://api.yalidine.app/v1/histories/${encodeURIComponent(tracking)}`,
        {
          "X-API-ID": settings.api_key,
          "X-API-TOKEN": settings.api_secret,
          Accept: "application/json",
        },
      );
    } else if (normalized.includes("ecotrack")) {
      for (const base of ecotrackBaseUrls()) {
        trackingData = await fetchJson(
          `${base.replace(/\/+$/, "")}/api/v1/get/tracking/info?tracking=${encodeURIComponent(
            tracking,
          )}`,
          {
            Authorization: `Bearer ${settings.api_key}`,
            Accept: "application/json",
          },
        );
        if (trackingData) break;
      }
    } else if (normalized.includes("zrexpress")) {
      trackingData = await fetchJson(
        `https://api.zrexpress.app/api/v1/parcels/${encodeURIComponent(tracking)}`,
        {
          "X-Api-Key": settings.api_key,
          "X-Tenant": settings.api_secret,
          Accept: "application/json",
        },
      );
    }

    if (!trackingData) continue;
    let returnStatus: string | null = null;
    if (normalized.includes("ecotrack")) {
      returnStatus = detectEcotrackReturn(trackingData);
    } else if (normalized.includes("zrexpress")) {
      returnStatus = detectZrExpressReturn(trackingData);
    }
    if (!returnStatus) returnStatus = detectReturn(trackingData);

    if (returnStatus) {
      const { error: insertError } = await supabase
        .from("buyer_return_events")
        .upsert(
          {
            buyer_id: order.buyer_id,
            order_id: Number(order.id),
            courier_id: courierId || courierName,
            status: returnStatus,
            returned_at: new Date().toISOString(),
          },
          { onConflict: "order_id,status" },
        );
      if (!insertError) inserted += 1;
    }

    const trackingStatus = detectTrackingStatus(trackingData);
    if (trackingStatus) {
      const isReturn =
        trackingStatus === "returned_to_sender" ||
        trackingStatus === "not_claimed" ||
        trackingStatus === "refused";
      const eventKey = `order:${order.id}:tracking:${trackingStatus}`;
      const payload = {
        i18n_key: isReturn ? "order.system.returned" : "order.system.tracking",
        status: trackingStatus,
        status_i18n: `order.status.${trackingStatus}`,
        tracking_number: tracking,
        courier_id: courierId,
        courier_name: courierName,
      };
      try {
        await supabase.rpc("post_order_event", {
          p_order_id: Number(order.id),
          p_event: "order_tracking",
          p_payload: payload,
          p_dedupe_key: eventKey,
        });
      } catch (_) {
        // Ignore tracking message errors
      }

      try {
        const { data: shipmentRow } = await supabase
          .from("shipments")
          .select("events,status,tracking_number,carrier,option,delivery_mode,label_url")
          .eq("order_id", Number(order.id))
          .maybeSingle();

        const existingEvents = (shipmentRow?.events as unknown as Array<Record<string, unknown>>) ?? [];
        const eventExists = existingEvents.some((e) => {
          const key = e?.key as string | undefined;
          const status = e?.status as string | undefined;
          return key === `status:${trackingStatus}` || status === trackingStatus;
        });
        const updatedEvents = eventExists
          ? existingEvents
          : [
              ...existingEvents,
              {
                key: `status:${trackingStatus}`,
                status: trackingStatus,
                title: trackingStatus,
                description: courierName || courierId || "",
                at: new Date().toISOString(),
              },
            ];

        if (shipmentRow) {
          await supabase
            .from("shipments")
            .update({
              status: trackingStatus,
              tracking_number: tracking,
              events: updatedEvents,
              carrier: shipmentRow.carrier ?? courierName ?? courierId,
              option: shipmentRow.option,
              delivery_mode: shipmentRow.delivery_mode,
              label_url: shipmentRow.label_url,
            })
            .eq("order_id", Number(order.id));
        } else {
          await supabase.from("shipments").insert({
            order_id: Number(order.id),
            tracking_number: tracking,
            status: trackingStatus,
            carrier: courierName ?? courierId,
            option: null,
            delivery_mode: null,
            label_url: null,
            events: updatedEvents,
          });
        }
      } catch (_) {
        // Ignore shipment timeline errors
      }
    }
  }

  if (inserted > 0) {
    await supabase.rpc("refresh_buyer_return_stats", {});
  }
  return inserted;
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") {
    return jsonResponse({ ok: false, message: "Method not allowed" }, 405);
  }

  const auth = req.headers.get("authorization") ?? "";
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !serviceKey) {
    return jsonResponse({ ok: false, message: "Server misconfigured" }, 500);
  }
  if (auth !== `Bearer ${serviceKey}`) {
    return jsonResponse({ ok: false, message: "Unauthorized" }, 401);
  }

  const supabase = createClient(url, serviceKey, {
    auth: { persistSession: false },
    global: { headers: { Authorization: auth } },
  });

  const { data: jobs, error } = await supabase.rpc("claim_jobs", {
    p_type: "create_shipment",
    p_limit: 5,
  });
  if (error) {
    return jsonResponse({ ok: false, message: error.message }, 500);
  }

  const results: Array<{ id: number; ok: boolean; error?: string }> = [];
  const jobsList = Array.isArray(jobs) ? jobs : [];

  for (const job of jobsList) {
    const jobId = job.id as number;
    try {
      const payload = { ...(job.payload ?? {}), async: false };
      const resp = await fetch(`${url}/functions/v1/create_shipment`, {
        method: "POST",
        headers: {
          Authorization: auth,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
      });
      const body = await resp.text();
      const ok = resp.ok;
      await supabase.rpc("complete_job", {
        p_id: jobId,
        p_success: ok,
        p_error: ok ? null : body,
      });
      results.push({ id: jobId, ok, error: ok ? undefined : body });
    } catch (e) {
      await supabase.rpc("complete_job", {
        p_id: jobId,
        p_success: false,
        p_error: e instanceof Error ? e.message : String(e),
      });
      results.push({
        id: jobId,
        ok: false,
        error: e instanceof Error ? e.message : String(e),
      });
    }
  }

  let cancelled = 0;
  let returns = 0;
  let purgedErrors = 0;
  try {
    const { data: cancelledCount } = await supabase.rpc("cancel_stale_orders", {});
    if (typeof cancelledCount === "number") cancelled = cancelledCount;
  } catch (_) {
    // Do not fail job runner if cancellation fails
  }
  try {
    returns = await syncBuyerReturns(supabase);
  } catch (_) {
    returns = 0;
  }

  try {
    const envRetention = Number(Deno.env.get("APP_ERRORS_RETENTION_DAYS") ?? "30");
    const retentionDays = Number.isFinite(envRetention) && envRetention > 0
      ? Math.floor(envRetention)
      : 30;
    const { data: purgedCount } = await supabase.rpc("cleanup_app_errors", {
      p_days: retentionDays,
    });
    if (typeof purgedCount === "number") purgedErrors = purgedCount;
  } catch (_) {
    purgedErrors = 0;
  }

  return jsonResponse({
    ok: true,
    processed: results.length,
    cancelled,
    returns,
    purged_errors: purgedErrors,
    results,
  });
});

