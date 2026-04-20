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

const normalizeCourier = (value: string) =>
  value.toLowerCase().replace(/[^a-z0-9]/g, "");

const normalizeDeliveryToken = (value: unknown) =>
  textValue(value).toLowerCase().replace(/[^a-z0-9]+/g, "");

const isArrangedDelivery = (value: unknown) => {
  const token = normalizeDeliveryToken(value);
  if (!token) return false;
  return token === "pickup" ||
    token === "livraisonaconvenir" ||
    token === "deliveryarranged" ||
    token === "arrangeddelivery" ||
    token === "remiseenmainpropre" ||
    token === "mainpropre";
};

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
    lower.includes("out for delivery") ||
    lower.includes("en livraison") ||
    lower.includes("mise en livraison") ||
    lower.includes("cours de livraison") ||
    lower.includes("attempt_delivery")
  ) {
    return "out_for_delivery";
  }

  if (
    lower.includes("picked") ||
    lower.includes("accepted_by_carrier") ||
    lower.includes("dispatched_to_driver") ||
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
type CourierFetchResult = { ok: boolean; data: unknown | null };

type ReturnsSyncMetrics = {
  orders_scanned: number;
  pending_orders: number;
  returns_inserted: number;
  insert_errors: number;
  courier_api_calls: number;
  courier_api_failures: number;
  tracking_updates: number;
  stats_refresh_error: boolean;
  sync_error: string | null;
};

const emptyReturnsMetrics = (): ReturnsSyncMetrics => ({
  orders_scanned: 0,
  pending_orders: 0,
  returns_inserted: 0,
  insert_errors: 0,
  courier_api_calls: 0,
  courier_api_failures: 0,
  tracking_updates: 0,
  stats_refresh_error: false,
  sync_error: null,
});

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
  let resp: Response;
  let lastError: unknown = null;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      resp = await fetch(url, init);
      if (!isRetryableStatus(resp.status) || attempt === maxAttempts) {
        return resp;
      }
      const retryAfterMs = parseRetryAfterMs(resp.headers.get("Retry-After"));
      const jitter = Math.floor(Math.random() * 120);
      const backoff = Math.min(300 * 2 ** (attempt - 1), 5000);
      await sleep((retryAfterMs ?? backoff) + jitter);
    } catch (error) {
      lastError = error;
      if (attempt === maxAttempts) break;
      const jitter = Math.floor(Math.random() * 120);
      const backoff = Math.min(300 * 2 ** (attempt - 1), 5000);
      await sleep(backoff + jitter);
    }
  }
  throw lastError instanceof Error ? lastError : new Error("network_retry_failed");
};

type CarrierRateWindow = { limit: number; seconds: number };

const syncRatePolicy = (carrierCode: string): CarrierRateWindow[] => {
  switch (carrierCode) {
    case "guepex":
      return [{ limit: 4, seconds: 1 }, { limit: 45, seconds: 60 }];
    case "ecotrack":
      return [{ limit: 45, seconds: 60 }];
    case "yalidine":
      return [{ limit: 8, seconds: 1 }, { limit: 80, seconds: 60 }];
    case "zrexpress":
      return [{ limit: 8, seconds: 1 }, { limit: 80, seconds: 60 }];
    default:
      return [{ limit: 6, seconds: 1 }, { limit: 60, seconds: 60 }];
  }
};

const enforceCourierSyncLimit = async (
  supabase: ReturnType<typeof createClient>,
  carrierCode: string,
) => {
  if (!carrierCode) return true;
  for (const window of syncRatePolicy(carrierCode)) {
    const ok = await consumeRateLimit(
      supabase,
      `carrier_sync:${carrierCode}:${window.seconds}`,
      window.limit,
      window.seconds,
    );
    if (!ok) return false;
  }
  return true;
};

const fetchJson = async (
  supabase: ReturnType<typeof createClient>,
  carrierCode: string,
  url: string,
  headers: HeadersInit,
): Promise<CourierFetchResult> => {
  const allowed = await enforceCourierSyncLimit(supabase, carrierCode);
  if (!allowed) return { ok: false, data: null };
  try {
    const resp = await fetchWithRetry(url, { method: "GET", headers });
    if (!resp.ok) return { ok: false, data: null };
    return { ok: true, data: await resp.json() };
  } catch {
    return { ok: false, data: null };
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

const guepexBaseUrls = () => {
  const envValue = (Deno.env.get("GUEPEX_BASE_URL") ?? "").trim();
  const candidates = [envValue, "https://api.guepex.app"];
  const seen = new Set<string>();
  return candidates.filter((v) => {
    const normalized = v.replace(/\/+$/, "");
    if (!normalized || seen.has(normalized)) return false;
    seen.add(normalized);
    return true;
  });
};

const parseEnvInt = (
  key: string,
  defaultValue: number,
  min: number,
  max: number,
) => {
  const raw = Number(Deno.env.get(key) ?? defaultValue.toString());
  if (!Number.isFinite(raw)) return defaultValue;
  return Math.min(Math.max(Math.floor(raw), min), max);
};

const normalizeReturnStatus = (status: string | null) => {
  if (!status) return null;
  if (status === "returned_to_sender") return status;
  if (status === "not_claimed") return status;
  if (status === "refused") return status;
  return null;
};

const normalizeCourierForEvent = (courierId: string, courierName: string) => {
  const normalized = normalizeCourier(courierId || courierName);
  if (!normalized) return null;
  if (normalized.includes("yalidine")) return "yalidine";
  if (normalized.includes("ecotrack")) return "ecotrack";
  if (normalized.includes("zrexpress")) return "zrexpress";
  if (normalized.includes("guepex")) return "guepex";
  return normalized.slice(0, 32);
};

const syncBuyerReturns = async (
  supabase: ReturnType<typeof createClient>,
): Promise<ReturnsSyncMetrics> => {
  const metrics = emptyReturnsMetrics();
  const since = new Date();
  since.setMonth(since.getMonth() - 12);
  const maxOrders = parseEnvInt("RETURNS_SYNC_MAX_ORDERS", 500, 20, 5000);
  const pageSize = parseEnvInt("RETURNS_SYNC_PAGE_SIZE", 100, 20, 500);
  const maxBatches = Math.ceil(maxOrders / pageSize) + 1;
  let inserted = 0;
  let scanned = 0;
  const settingsCache = new Map<string, { api_key: string; api_secret: string } | null>();

  for (let batch = 0; batch < maxBatches && scanned < maxOrders; batch++) {
    const from = batch * pageSize;
    const to = from + pageSize - 1;
    const { data: orders, error: ordersError } = await supabase
      .from("orders")
      .select("id,buyer_id,seller_id,courier_id,courier_name,tracking_number,created_at")
      .not("tracking_number", "is", null)
      .gte("created_at", since.toISOString())
      .order("created_at", { ascending: false })
      .range(from, to);
    if (ordersError) throw ordersError;

    const fetched = Array.isArray(orders) ? orders : [];
    if (fetched.length === 0) break;

    const remaining = Math.max(maxOrders - scanned, 0);
    const orderList = fetched.slice(0, remaining);
    scanned += orderList.length;
    if (orderList.length === 0) break;

    const orderIds = orderList
      .map((order) => Number(order?.id))
      .filter((id) => Number.isFinite(id)) as number[];
    if (orderIds.length === 0) continue;

    const { data: existingEvents, error: existingError } = await supabase
      .from("buyer_return_events")
      .select("order_id")
      .in("order_id", orderIds);
    if (existingError) throw existingError;

    const existingOrders = new Set(
      (existingEvents ?? [])
        .map((row) => Number(row.order_id))
        .filter((id) => Number.isFinite(id)),
    );

    const pending = orderList.filter((order) => {
      const orderId = Number(order?.id);
      return order?.tracking_number && Number.isFinite(orderId) && !existingOrders.has(orderId);
    });
    metrics.pending_orders += pending.length;
    if (pending.length === 0) continue;

    const missingPairs = new Map<string, { sellerId: string; courierId: string }>();
    for (const order of pending) {
      const sellerId = order.seller_id?.toString() ?? "";
      const courierId = order.courier_id?.toString() ?? "";
      if (!sellerId || !courierId) continue;
      const key = `${sellerId}:${courierId}`;
      if (!settingsCache.has(key)) {
        missingPairs.set(key, { sellerId, courierId });
      }
    }

    if (missingPairs.size > 0) {
      const sellerIds = Array.from(new Set(Array.from(missingPairs.values()).map((v) => v.sellerId)));
      const courierIds = Array.from(new Set(Array.from(missingPairs.values()).map((v) => v.courierId)));

      const { data: settings, error: settingsError } = await supabase
        .from("seller_delivery_settings")
        .select("owner_id,courier_id,api_key,api_secret")
        .in("owner_id", sellerIds)
        .in("courier_id", courierIds);
      if (settingsError) throw settingsError;

      for (const key of missingPairs.keys()) {
        settingsCache.set(key, null);
      }
      for (const row of settings ?? []) {
        if (!row?.owner_id || !row?.courier_id || !row?.api_key) continue;
        settingsCache.set(`${row.owner_id}:${row.courier_id}`, {
          api_key: row.api_key,
          api_secret: row.api_secret ?? "",
        });
      }
    }

    for (const order of pending) {
      const courierId = order.courier_id ?? "";
      const courierName = order.courier_name ?? "";
      const normalized = normalizeCourier(`${courierId} ${courierName}`);
      const settings = settingsCache.get(`${order.seller_id}:${courierId}`) ?? null;
      if (!settings) continue;

      const tracking = order.tracking_number?.toString() ?? "";
      if (!tracking) continue;

      let trackingData: unknown = null;
      if (normalized.includes("yalidine")) {
        metrics.courier_api_calls += 1;
        const response = await fetchJson(
          supabase,
          "yalidine",
          `https://api.yalidine.app/v1/histories/${encodeURIComponent(tracking)}`,
          {
            "X-API-ID": settings.api_key,
            "X-API-TOKEN": settings.api_secret,
            Accept: "application/json",
          },
        );
        if (!response.ok) metrics.courier_api_failures += 1;
        trackingData = response.data;
      } else if (normalized.includes("ecotrack")) {
        for (const base of ecotrackBaseUrls()) {
          metrics.courier_api_calls += 1;
          const response = await fetchJson(
            supabase,
            "ecotrack",
            `${base.replace(/\/+$/, "")}/api/v1/get/tracking/info?tracking=${encodeURIComponent(
              tracking,
            )}`,
            {
              Authorization: `Bearer ${settings.api_key}`,
              Accept: "application/json",
            },
          );
          if (!response.ok) metrics.courier_api_failures += 1;
          trackingData = response.data;
          if (trackingData) break;
        }
      } else if (normalized.includes("zrexpress")) {
        metrics.courier_api_calls += 1;
        const response = await fetchJson(
          supabase,
          "zrexpress",
          `https://api.zrexpress.app/api/v1/parcels/${encodeURIComponent(tracking)}`,
          {
            "X-Api-Key": settings.api_key,
            "X-Tenant": settings.api_secret,
            Accept: "application/json",
          },
        );
        if (!response.ok) metrics.courier_api_failures += 1;
        trackingData = response.data;
      } else if (normalized.includes("guepex")) {
        if (!settings.api_secret) continue;
        for (const base of guepexBaseUrls()) {
          metrics.courier_api_calls += 1;
          let response = await fetchJson(
            supabase,
            "guepex",
            `${base.replace(/\/+$/, "")}/v1/histories/${encodeURIComponent(tracking)}`,
            {
              "X-API-ID": settings.api_key,
              "X-API-TOKEN": settings.api_secret,
              Accept: "application/json",
            },
          );
          if (!response.ok) {
            response = await fetchJson(
              supabase,
              "guepex",
              `${base.replace(/\/+$/, "")}/v1/histories?tracking=${encodeURIComponent(tracking)}`,
              {
                "X-API-ID": settings.api_key,
                "X-API-TOKEN": settings.api_secret,
                Accept: "application/json",
              },
            );
          }
          if (!response.ok) metrics.courier_api_failures += 1;
          trackingData = response.data;
          if (trackingData) break;
        }
      }

      if (!trackingData) continue;
      let returnStatus: string | null = null;
      if (normalized.includes("ecotrack")) {
        returnStatus = detectEcotrackReturn(trackingData);
      } else if (normalized.includes("zrexpress")) {
        returnStatus = detectZrExpressReturn(trackingData);
      }
      if (!returnStatus) returnStatus = detectReturn(trackingData);
      const safeReturnStatus = normalizeReturnStatus(returnStatus);

      if (safeReturnStatus) {
        const safeCourierId = normalizeCourierForEvent(courierId, courierName);
        const { error: insertError } = await supabase
          .from("buyer_return_events")
          .upsert(
            {
              buyer_id: order.buyer_id,
              order_id: Number(order.id),
              // Keep return event minimal: no buyer name/phone/address copied here.
              courier_id: safeCourierId,
              status: safeReturnStatus,
              returned_at: new Date().toISOString(),
            },
            { onConflict: "order_id,status" },
          );
        if (!insertError) {
          inserted += 1;
        } else {
          metrics.insert_errors += 1;
        }
      }

      const trackingStatus = detectTrackingStatus(trackingData);
      if (trackingStatus) {
        metrics.tracking_updates += 1;
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
                  i18n_key: `order.status.${trackingStatus}`,
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
  }

  metrics.orders_scanned = scanned;
  metrics.returns_inserted = inserted;
  if (inserted > 0) {
    try {
      await supabase.rpc("refresh_buyer_return_stats", {});
    } catch (_) {
      metrics.stats_refresh_error = true;
    }
  }
  return metrics;
};

const sendLabelReminders = async (
  supabase: ReturnType<typeof createClient>,
): Promise<number> => {
  const now = Date.now();
  const olderThan = new Date(now - 3 * 24 * 60 * 60 * 1000).toISOString();
  const newerThan = new Date(now - 2 * 24 * 60 * 60 * 1000).toISOString();
  const maxOrders = parseEnvInt("LABEL_REMINDER_MAX_ORDERS", 500, 20, 5000);

  const { data: orders, error: ordersError } = await supabase
    .from("orders")
    .select("id,status,label_url,tracking_number,created_at,delivery_method,shipping_option")
    .in("status", ["pending", "paid"])
    .gte("created_at", olderThan)
    .lt("created_at", newerThan)
    .order("created_at", { ascending: true })
    .limit(maxOrders);
  if (ordersError) throw ordersError;

  const orderList = Array.isArray(orders) ? orders : [];
  if (orderList.length === 0) return 0;

  const orderIds = orderList
    .map((order) => Number(order?.id))
    .filter((id) => Number.isFinite(id)) as number[];
  if (orderIds.length === 0) return 0;

  const { data: shipments, error: shipmentsError } = await supabase
    .from("shipments")
    .select("order_id,label_url,tracking_number")
    .in("order_id", orderIds);
  if (shipmentsError) throw shipmentsError;

  const shipmentByOrder = new Map<
    number,
    { label_url: string | null; tracking_number: string | null }
  >();
  for (const row of shipments ?? []) {
    const id = Number(row?.order_id);
    if (!Number.isFinite(id)) continue;
    shipmentByOrder.set(id, {
      label_url: row?.label_url ?? null,
      tracking_number: row?.tracking_number ?? null,
    });
  }

  let sent = 0;
  for (const order of orderList) {
    const orderId = Number(order?.id);
    if (!Number.isFinite(orderId)) continue;
    if (
      isArrangedDelivery(order?.delivery_method) ||
      isArrangedDelivery(order?.shipping_option)
    ) {
      continue;
    }

    const hasOrderLabel =
      textValue(order?.label_url) !== "" ||
      textValue(order?.tracking_number) !== "";
    const shipment = shipmentByOrder.get(orderId);
    const hasShipmentLabel = shipment != null &&
      (textValue(shipment.label_url) !== "" ||
        textValue(shipment.tracking_number) !== "");
    if (hasOrderLabel || hasShipmentLabel) continue;

    try {
      await supabase.rpc("post_order_event", {
        p_order_id: orderId,
        p_event: "order_label_reminder",
        p_payload: {
          i18n_key: "order.system.label_reminder",
          status: "pending",
          status_i18n: "order.status.pending",
        },
        p_dedupe_key: `order:${orderId}:label_reminder_48h`,
      });
      sent += 1;
    } catch (_) {
      // Do not fail runner on one reminder event.
    }
  }

  return sent;
};

const isFinalShipmentStatus = (value: unknown) => {
  const status = textValue(value).toLowerCase();
  return status === "delivered" ||
    status === "returned_to_sender" ||
    status === "not_claimed" ||
    status === "refused" ||
    status === "cancelled";
};

const hasCarrierProgressEvent = (events: unknown) => {
  if (!Array.isArray(events)) return false;
  for (const event of events) {
    const status = textValue(
      typeof event === "object" && event !== null
        ? (event as Record<string, unknown>).status
        : "",
    ).toLowerCase();
    if (!status) continue;
    if (isFinalShipmentStatus(status)) return true;
    if (status !== "pending" && status !== "validated" && status !== "shipped") {
      return true;
    }
  }
  return false;
};

type CarrierScanReminderMetrics = {
  scanned: number;
  sent: number;
  skipped_bad_order_id: number;
  skipped_no_order: number;
  skipped_arranged: number;
  skipped_order_closed: number;
  skipped_recent: number;
  skipped_no_label: number;
  skipped_final: number;
  skipped_progress: number;
};

const emptyCarrierScanReminderMetrics = (): CarrierScanReminderMetrics => ({
  scanned: 0,
  sent: 0,
  skipped_bad_order_id: 0,
  skipped_no_order: 0,
  skipped_arranged: 0,
  skipped_order_closed: 0,
  skipped_recent: 0,
  skipped_no_label: 0,
  skipped_final: 0,
  skipped_progress: 0,
});

const sendCarrierScanReminders = async (
  supabase: ReturnType<typeof createClient>,
): Promise<CarrierScanReminderMetrics> => {
  const metrics = emptyCarrierScanReminderMetrics();
  const now = Date.now();
  const olderThan = new Date(now - 4 * 24 * 60 * 60 * 1000).toISOString();
  const maxOrders = parseEnvInt("CARRIER_SCAN_REMINDER_MAX_ORDERS", 500, 20, 5000);
  const queries = [
    {
      select: "order_id,status,label_url,tracking_number,created_at,events",
      useCreatedFilter: true,
      orderByCreated: true,
    },
    {
      select: "order_id,status,label_url,tracking_number,created_at",
      useCreatedFilter: true,
      orderByCreated: true,
    },
    {
      select: "order_id,status,label_url,tracking_number",
      useCreatedFilter: false,
      orderByCreated: false,
    },
  ];

  const isMissingColumnError = (
    error: { code?: string; message?: string; details?: string; hint?: string } | null,
  ) => {
    if (!error) return false;
    const blob = `${error.message ?? ""} ${error.details ?? ""} ${error.hint ?? ""}`.toLowerCase();
    return blob.includes("column") &&
      (blob.includes("events") || blob.includes("updated_at") || blob.includes("created_at"));
  };

  let shipments: Array<Record<string, unknown>> = [];
  let lastError: { code?: string; message?: string } | null = null;
  for (const query of queries) {
    let builder = supabase
      .from("shipments")
      .select(query.select)
      .in("status", ["pending", "validated", "shipped"])
      .limit(maxOrders);
    if (query.useCreatedFilter) {
      builder = builder.lt("created_at", olderThan);
    }
    if (query.orderByCreated) {
      builder = builder.order("created_at", { ascending: true });
    } else {
      builder = builder.order("order_id", { ascending: true });
    }
    const res = await builder;
    if (!res.error) {
      shipments = (res.data ?? []) as Array<Record<string, unknown>>;
      lastError = null;
      break;
    }
    lastError = res.error;
    if (!isMissingColumnError(res.error)) {
      throw res.error;
    }
  }
  if (lastError) throw lastError;
  if (shipments.length === 0) return metrics;
  metrics.scanned = shipments.length;

  const orderIds = Array.from(
    new Set(
      shipments
        .map((shipment) => Number(shipment?.order_id))
        .filter((id) => Number.isFinite(id)),
    ),
  ) as number[];
  if (orderIds.length === 0) return metrics;

  const orderSelects = [
    "id,status,created_at,delivery_method,shipping_option,courier_id,courier_name",
    "id,status,created_at,delivery_method,shipping_option,courier_id",
    "id,status,created_at,delivery_method,shipping_option,courier_name",
    "id,status,created_at,delivery_method,shipping_option",
  ];
  let ordersData: Array<Record<string, unknown>> = [];
  let ordersError: { code?: string; message?: string; details?: string; hint?: string } | null = null;
  for (const selectCols of orderSelects) {
    const res = await supabase
      .from("orders")
      .select(selectCols)
      .in("id", orderIds);
    if (!res.error) {
      ordersData = (res.data ?? []) as Array<Record<string, unknown>>;
      ordersError = null;
      break;
    }
    ordersError = res.error;
    if (!isMissingColumnError(res.error)) {
      throw res.error;
    }
  }
  if (ordersError) throw ordersError;
  const orderById = new Map<number, Record<string, unknown>>();
  for (const orderRow of ordersData ?? []) {
    const id = Number(orderRow?.id);
    if (!Number.isFinite(id)) continue;
    orderById.set(id, orderRow as Record<string, unknown>);
  }

  for (const shipment of shipments) {
    const orderId = Number(shipment?.order_id);
    if (!Number.isFinite(orderId)) {
      metrics.skipped_bad_order_id += 1;
      continue;
    }

    const order = orderById.get(orderId);
    if (!order) {
      metrics.skipped_no_order += 1;
      continue;
    }

    if (
      isArrangedDelivery(order?.delivery_method) ||
      isArrangedDelivery(order?.shipping_option)
    ) {
      metrics.skipped_arranged += 1;
      continue;
    }

    const orderStatus = textValue(order?.status).toLowerCase();
    if (orderStatus === "cancelled" || orderStatus === "delivered") {
      metrics.skipped_order_closed += 1;
      continue;
    }

    const shipmentCreatedAt = textValue(shipment?.created_at);
    const orderCreatedAt = textValue(order?.created_at);
    const anchorAt = shipmentCreatedAt || orderCreatedAt;
    if (!anchorAt) {
      metrics.skipped_recent += 1;
      continue;
    }
    const anchorMs = Date.parse(anchorAt);
    if (!Number.isFinite(anchorMs) || anchorMs > now - 4 * 24 * 60 * 60 * 1000) {
      metrics.skipped_recent += 1;
      continue;
    }

    const hasLabelData = textValue(shipment?.label_url) !== "" ||
      textValue(shipment?.tracking_number) !== "";
    if (!hasLabelData) {
      metrics.skipped_no_label += 1;
      continue;
    }
    if (isFinalShipmentStatus(shipment?.status)) {
      metrics.skipped_final += 1;
      continue;
    }
    if (hasCarrierProgressEvent(shipment?.events)) {
      metrics.skipped_progress += 1;
      continue;
    }

    const currentStatus = textValue(shipment?.status).toLowerCase();
    const safeStatus = /^[a-z0-9_]+$/.test(currentStatus) && currentStatus
      ? currentStatus
      : "shipped";

    try {
      await supabase.rpc("post_order_event", {
        p_order_id: orderId,
        p_event: "order_carrier_scan_reminder",
        p_payload: {
          i18n_key: "order.system.carrier_scan_reminder",
          status: safeStatus,
          status_i18n: `order.status.${safeStatus}`,
          tracking_number: textValue(shipment?.tracking_number) || null,
          courier_id: textValue(order?.courier_id) || null,
          courier_name: textValue(order?.courier_name) || null,
        },
        p_dedupe_key: `order:${orderId}:carrier_scan_reminder_96h`,
      });
      metrics.sent += 1;
    } catch (_) {
      // Do not fail runner on one reminder event.
    }
  }

  return metrics;
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
      const resp = await fetchWithRetry(
        `${url}/functions/v1/create_shipment`,
        {
          method: "POST",
          headers: {
            Authorization: auth,
            "Content-Type": "application/json",
          },
          body: JSON.stringify(payload),
        },
        3,
      );
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
  let labelRemindersSent = 0;
  let carrierScanRemindersSent = 0;
  let carrierScanReminderDebug = emptyCarrierScanReminderMetrics();
  let returnsMetrics = emptyReturnsMetrics();
  let purgedErrors = 0;
  try {
    labelRemindersSent = await sendLabelReminders(supabase);
  } catch (_) {
    labelRemindersSent = 0;
  }
  try {
    carrierScanReminderDebug = await sendCarrierScanReminders(supabase);
    carrierScanRemindersSent = carrierScanReminderDebug.sent;
  } catch (_) {
    carrierScanRemindersSent = 0;
  }
  try {
    const { data: cancelledCount } = await supabase.rpc("cancel_stale_orders", {});
    if (typeof cancelledCount === "number") cancelled = cancelledCount;
  } catch (_) {
    // Do not fail job runner if cancellation fails
  }
  try {
    returnsMetrics = await syncBuyerReturns(supabase);
  } catch (e) {
    returnsMetrics.sync_error = e instanceof Error ? e.message : String(e);
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

  const createShipmentFailures = results.filter((item) => !item.ok).length;
  return jsonResponse({
    ok: true,
    processed: results.length,
    create_shipment_failures: createShipmentFailures,
    label_reminders_sent: labelRemindersSent,
    carrier_scan_reminders_sent: carrierScanRemindersSent,
    carrier_scan_reminder_debug: carrierScanReminderDebug,
    cancelled,
    returns: returnsMetrics.returns_inserted,
    returns_metrics: returnsMetrics,
    purged_errors: purgedErrors,
    results,
  });
});

