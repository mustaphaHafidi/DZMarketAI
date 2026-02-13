import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type Selection = Record<string, unknown>;

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

const textValue = (value: unknown) =>
  typeof value === "string" ? value.trim() : value == null ? "" : String(value);

const numberValue = (value: unknown, fallback = 0) => {
  if (typeof value === "number") return value;
  const parsed = Number(textValue(value));
  return Number.isFinite(parsed) ? parsed : fallback;
};

const intValue = (value: unknown, fallback: number) => {
  const parsed = Number(textValue(value));
  if (!Number.isFinite(parsed)) return fallback;
  return Math.round(parsed);
};

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

const pick = (selection: Selection | undefined, key: string) =>
  selection ? selection[key] : undefined;

const clientIp = (req: Request) => {
  const forwarded = req.headers.get("x-forwarded-for") ?? "";
  if (forwarded) return forwarded.split(",")[0].trim();
  return (
    req.headers.get("cf-connecting-ip") ??
    req.headers.get("x-real-ip") ??
    ""
  ).trim();
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
  if (Number.isFinite(seconds) && seconds > 0) {
    return Math.min(seconds * 1000, 15000);
  }
  const dateMs = Date.parse(value);
  if (Number.isFinite(dateMs)) {
    const delta = dateMs - Date.now();
    if (delta > 0) return Math.min(delta, 15000);
  }
  return null;
};

const isRetryableStatus = (status: number) =>
  status === 408 || status === 429 || status >= 500;

type RetryPolicy = {
  maxAttempts?: number;
  baseDelayMs?: number;
  maxDelayMs?: number;
  timeoutMs?: number;
};

const fetchWithRetry = async (
  url: string,
  init: RequestInit,
  policy: RetryPolicy = {},
): Promise<Response> => {
  const maxAttempts = Math.max(1, policy.maxAttempts ?? 4);
  const baseDelayMs = Math.max(100, policy.baseDelayMs ?? 350);
  const maxDelayMs = Math.max(baseDelayMs, policy.maxDelayMs ?? 5000);
  const timeoutMs = Math.max(1000, policy.timeoutMs ?? 12000);

  let lastError: unknown = null;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetch(url, { ...init, signal: controller.signal });
      clearTimeout(timeoutId);
      if (!isRetryableStatus(response.status) || attempt === maxAttempts) {
        return response;
      }
      const retryAfterMs = parseRetryAfterMs(response.headers.get("Retry-After"));
      const jitter = Math.floor(Math.random() * 120);
      const backoff = Math.min(baseDelayMs * 2 ** (attempt - 1), maxDelayMs);
      await sleep((retryAfterMs ?? backoff) + jitter);
      continue;
    } catch (error) {
      clearTimeout(timeoutId);
      lastError = error;
      if (attempt === maxAttempts) break;
      const jitter = Math.floor(Math.random() * 120);
      const backoff = Math.min(baseDelayMs * 2 ** (attempt - 1), maxDelayMs);
      await sleep(backoff + jitter);
    }
  }
  throw lastError instanceof Error
    ? lastError
    : new Error("network_retry_failed");
};

type CarrierRateWindow = { limit: number; seconds: number };

const carrierRatePolicy = (carrierCode: string): CarrierRateWindow[] => {
  switch (carrierCode) {
    case "guepex":
      return [
        { limit: 4, seconds: 1 },
        { limit: 45, seconds: 60 },
        { limit: 900, seconds: 3600 },
      ];
    case "ecotrack":
      return [
        { limit: 45, seconds: 60 },
        { limit: 1300, seconds: 3600 },
        { limit: 13000, seconds: 86400 },
      ];
    case "yalidine":
      return [
        { limit: 8, seconds: 1 },
        { limit: 90, seconds: 60 },
      ];
    case "zrexpress":
      return [
        { limit: 8, seconds: 1 },
        { limit: 80, seconds: 60 },
      ];
    default:
      return [
        { limit: 6, seconds: 1 },
        { limit: 60, seconds: 60 },
      ];
  }
};

const enforceCarrierRateLimit = async (
  supabase: ReturnType<typeof createClient>,
  carrierCode: string,
  ownerId: string,
) => {
  if (!carrierCode || !ownerId) return true;
  const windows = carrierRatePolicy(carrierCode);
  for (const window of windows) {
    const ok = await consumeRateLimit(
      supabase,
      `carrier_api:${carrierCode}:${ownerId}:${window.seconds}`,
      window.limit,
      window.seconds,
    );
    if (!ok) return false;
  }
  return true;
};

const carrierFetch = async (
  supabase: ReturnType<typeof createClient>,
  carrierCode: string,
  ownerId: string,
  url: string,
  init: RequestInit,
) => {
  const allowed = await enforceCarrierRateLimit(supabase, carrierCode, ownerId);
  if (!allowed) return null;
  return fetchWithRetry(url, init);
};

const loadLabelBytes = async (labelValue: string) => {
  const trimmed = labelValue.trim();
  if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
    const resp = await fetchWithRetry(trimmed, { method: "GET" }, {
      maxAttempts: 3,
      baseDelayMs: 350,
      maxDelayMs: 3000,
      timeoutMs: 15000,
    });
    if (!resp.ok) throw new Error(`Label download failed: ${resp.status}`);
    return new Uint8Array(await resp.arrayBuffer());
  }
  const base64Prefix = /^data:.*;base64,/i;
  const cleaned = trimmed.replace(base64Prefix, "");
  const binary = atob(cleaned);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
};

const uploadLabel = async (
  supabase: ReturnType<typeof createClient>,
  sellerId: string,
  fileName: string,
  bytes: Uint8Array,
) => {
  const path = `${sellerId}/${crypto.randomUUID()}-${fileName}`;
  const { error: uploadError } = await supabase.storage
    .from("labels")
    .upload(path, bytes, { contentType: "application/pdf", upsert: true });
  if (uploadError) throw new Error(uploadError.message);

  const { data, error } = await supabase.storage
    .from("labels")
    .createSignedUrl(path, 60 * 60 * 24);
  if (error) throw new Error(error.message);
  return data?.signedUrl ?? "";
};

const isPdfBytes = (bytes: Uint8Array) =>
  bytes.length > 4 &&
  bytes[0] === 0x25 &&
  bytes[1] === 0x50 &&
  bytes[2] === 0x44 &&
  bytes[3] === 0x46;

const decodeBytes = (bytes: Uint8Array) =>
  new TextDecoder().decode(bytes).trim();

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

const guepexBaseUrl = () =>
  (Deno.env.get("GUEPEX_BASE_URL") ?? "https://api.guepex.app")
    .trim()
    .replace(/\/+$/, "");

const joinUrl = (base: string, path: string) =>
  `${base.replace(/\/+$/, "")}${path}`;

type CourierParcelRules = {
  minWeightKg: number;
  maxWeightKg: number;
  maxHeightCm: number;
  maxWidthCm: number;
  maxLengthCm: number;
  maxVolumeCm3: number;
  maxDeclaredValue: number;
};

type ParcelValidationError = {
  message: string;
  details?: Record<string, unknown>;
};

const genericParcelRules: CourierParcelRules = {
  minWeightKg: 1,
  maxWeightKg: 60,
  maxHeightCm: 200,
  maxWidthCm: 200,
  maxLengthCm: 200,
  maxVolumeCm3: 8000000,
  maxDeclaredValue: 99999999,
};

const parcelRulesForCourier = (normalizedCourier: string): CourierParcelRules => {
  if (normalizedCourier.includes("yalidine")) return genericParcelRules;
  if (normalizedCourier.includes("ecotrack")) return genericParcelRules;
  if (normalizedCourier.includes("zrexpress")) return genericParcelRules;
  if (normalizedCourier.includes("guepex")) return genericParcelRules;
  return genericParcelRules;
};

const canonicalCourierCode = (
  courierId: string,
  courierName: string,
  normalizedCourier: string,
) => {
  const normalizeCourier = (value: string) =>
    value.toLowerCase().replace(/[^a-z0-9]/g, "");
  const idKey = normalizeCourier(courierId);
  const nameKey = normalizeCourier(courierName);
  const merged = normalizedCourier || `${idKey}${nameKey}`;
  if (merged.includes("yalidine")) return "yalidine";
  if (merged.includes("ecotrack")) return "ecotrack";
  if (merged.includes("zrexpress")) return "zrexpress";
  if (merged.includes("guepex")) return "guepex";
  return idKey || "";
};

const loadParcelRulesForCourier = async (
  supabaseAdmin: ReturnType<typeof createClient>,
  courierCode: string,
  normalizedCourier: string,
): Promise<CourierParcelRules> => {
  const fallback = parcelRulesForCourier(normalizedCourier);
  if (!courierCode) return fallback;
  try {
    const { data, error } = await supabaseAdmin
      .from("courier_parcel_rules")
      .select(
        "min_weight_kg,max_weight_kg,max_height_cm,max_width_cm," +
          "max_length_cm,max_volume_cm3,max_declared_value",
      )
      .eq("courier_code", courierCode)
      .maybeSingle();
    if (error || !data) return fallback;
    return {
      minWeightKg: intValue((data as Record<string, unknown>).min_weight_kg, fallback.minWeightKg),
      maxWeightKg: intValue((data as Record<string, unknown>).max_weight_kg, fallback.maxWeightKg),
      maxHeightCm: intValue((data as Record<string, unknown>).max_height_cm, fallback.maxHeightCm),
      maxWidthCm: intValue((data as Record<string, unknown>).max_width_cm, fallback.maxWidthCm),
      maxLengthCm: intValue((data as Record<string, unknown>).max_length_cm, fallback.maxLengthCm),
      maxVolumeCm3: intValue((data as Record<string, unknown>).max_volume_cm3, fallback.maxVolumeCm3),
      maxDeclaredValue: numberValue(
        (data as Record<string, unknown>).max_declared_value,
        fallback.maxDeclaredValue,
      ),
    };
  } catch {
    return fallback;
  }
};

const validateParcelAgainstRules = ({
  rules,
  weightKg,
  heightCm,
  widthCm,
  lengthCm,
  declaredValue,
  insuranceActive,
}: {
  rules: CourierParcelRules;
  weightKg: number;
  heightCm: number;
  widthCm: number;
  lengthCm: number;
  declaredValue: number;
  insuranceActive: boolean;
}): ParcelValidationError | null => {
  if (weightKg < rules.minWeightKg || weightKg > rules.maxWeightKg) {
    return {
      message: "parcel_weight_out_of_range",
      details: { min: rules.minWeightKg, max: rules.maxWeightKg, value: weightKg },
    };
  }
  if (heightCm < 0 || heightCm > rules.maxHeightCm) {
    return {
      message: "parcel_height_out_of_range",
      details: { max: rules.maxHeightCm, value: heightCm },
    };
  }
  if (widthCm < 0 || widthCm > rules.maxWidthCm) {
    return {
      message: "parcel_width_out_of_range",
      details: { max: rules.maxWidthCm, value: widthCm },
    };
  }
  if (lengthCm < 0 || lengthCm > rules.maxLengthCm) {
    return {
      message: "parcel_length_out_of_range",
      details: { max: rules.maxLengthCm, value: lengthCm },
    };
  }
  const volume = heightCm * widthCm * lengthCm;
  if (volume > rules.maxVolumeCm3) {
    return {
      message: "parcel_volume_out_of_range",
      details: { max: rules.maxVolumeCm3, value: volume },
    };
  }
  if (
    insuranceActive &&
    declaredValue > 0 &&
    declaredValue > rules.maxDeclaredValue
  ) {
    return {
      message: "parcel_declared_value_out_of_range",
      details: { max: rules.maxDeclaredValue, value: declaredValue },
    };
  }
  return null;
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ ok: false, message: "Method not allowed" }, 405);

  const auth = req.headers.get("authorization") ?? "";
  if (!auth.startsWith("Bearer ")) {
    return jsonResponse({ ok: false, message: "Unauthorized" }, 401);
  }

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ ok: false, message: "Invalid JSON" }, 400);
  }

  const orderId = textValue(payload.order_id);
  if (!orderId) return jsonResponse({ ok: false, message: "Missing order_id" }, 400);

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !serviceKey) {
    return jsonResponse({ ok: false, message: "Server misconfigured" }, 500);
  }

  // Two clients:
  // - supabaseUser: carries the caller JWT to respect RLS on orders/shipments/messages.
  // - supabaseAdmin: pure service-role, used only for private seller credentials (no Authorization override).
  const supabaseUser = createClient(url, serviceKey, {
    auth: { persistSession: false },
    global: { headers: { Authorization: auth } },
  });
  const supabaseAdmin = createClient(url, serviceKey, {
    auth: { persistSession: false },
  });

  const isServiceRole = auth === `Bearer ${serviceKey}`;
  const { data: userData, error: userError } = await supabaseUser.auth.getUser();
  if (!isServiceRole && (userError || !userData?.user)) {
    return jsonResponse({ ok: false, message: "Unauthorized" }, 401);
  }
  const userId = userData?.user?.id ?? "";
  const ip = clientIp(req);

  try {
    const userOk = await consumeRateLimit(
      supabaseUser,
      `ship:${userId || "unknown"}`,
      6,
      60,
    );
    const ipOk = await consumeRateLimit(
      supabaseUser,
      `ship_ip:${ip || "unknown"}`,
      30,
      60,
    );
    if (!userOk || !ipOk) {
      await supabaseUser.rpc("log_abuse", {
        p_user_id: userId,
        p_ip: ip,
        p_type: "rate_limit",
        p_details: { action: "create_shipment" },
      });
      return jsonResponse(
        { ok: false, message: "Rate limit exceeded" },
        429,
      );
    }
  } catch {
    return jsonResponse({ ok: false, message: "Rate limit error" }, 500);
  }

  const baseOrderSelect =
    "id, seller_id, buyer_id, courier_id, courier_name, delivery_method, shipping_option, shipping_cost, tracking_number, label_url, status";
  let order = null;
  let orderError = null;
  {
    const res = await supabaseUser
      .from("orders")
      .select(`${baseOrderSelect}, shipping_selection`)
      .eq("id", orderId)
      .maybeSingle();
    order = res.data;
    orderError = res.error;
  }
  if (orderError && (orderError.code === "42703" ||
      `${orderError.message}`.includes("shipping_selection"))) {
    const res = await supabaseUser
      .from("orders")
      .select(baseOrderSelect)
      .eq("id", orderId)
      .maybeSingle();
    order = res.data;
    orderError = res.error;
  }
  if (orderError || !order) {
    return jsonResponse({ ok: false, message: "Order not found" }, 404);
  }
  const orderStatus = textValue(order.status).toLowerCase();
  if (orderStatus === "cancelled") {
    return jsonResponse({ ok: false, message: "Order cancelled" }, 409);
  }
  const effectiveUserId = isServiceRole ? order.seller_id : userId;
  if (!effectiveUserId) {
    return jsonResponse({ ok: false, message: "Unauthorized" }, 401);
  }
  if (!isServiceRole && order.seller_id !== effectiveUserId) {
    return jsonResponse({ ok: false, message: "Forbidden" }, 403);
  }

  const { data: existingShipment } = await supabaseUser
    .from("shipments")
    .select("tracking_number, label_url")
    .eq("order_id", orderId)
    .maybeSingle();
  if (existingShipment?.label_url && existingShipment?.tracking_number) {
    return jsonResponse({
      ok: true,
      tracking_number: existingShipment.tracking_number,
      label_url: existingShipment.label_url,
    });
  }

  const courierId =
    textValue(payload.courier_id) || textValue(order.courier_id);
  const courierName =
    textValue(payload.courier_name) || textValue(order.courier_name);
  if (!courierId && !courierName) {
    return jsonResponse({ ok: false, message: "Missing courier info" }, 400);
  }

  const selection =
    (payload.selection as Selection | undefined) ??
    (order?.shipping_selection as Selection | undefined);
  const deliveryMode =
    textValue(payload.delivery_mode) || textValue(order.delivery_method);
  const shippingOption =
    textValue(payload.shipping_option) || textValue(order.shipping_option);
  const shippingCost =
    numberValue(payload.shipping_cost, numberValue(order.shipping_cost, 0));

  if (isArrangedDelivery(deliveryMode) || isArrangedDelivery(shippingOption)) {
    return jsonResponse({ ok: false, message: "arranged_delivery_no_label" }, 409);
  }

  if (payload.async === true && !isServiceRole) {
    const { data: jobId } = await supabaseUser.rpc("enqueue_job", {
      p_type: "create_shipment",
      p_payload: payload,
      p_run_at: null,
    });
    return jsonResponse({ ok: true, queued: true, job_id: jobId });
  }

  const { data: settingsRow, error: settingsError } = await supabaseAdmin
    .from("seller_delivery_settings")
    .select("api_key, api_secret, sender_id, extra")
    .eq("owner_id", effectiveUserId)
    .eq("courier_id", courierId)
    .maybeSingle();
  if (settingsError || !settingsRow?.api_key) {
    return jsonResponse({ ok: false, message: "Missing courier settings" }, 400);
  }

  const normalizeCourier = (value: string) =>
    value.toLowerCase().replace(/[^a-z0-9]/g, "");
  const normalizedCourier = normalizeCourier(`${courierId} ${courierName}`);
  const courierCode = canonicalCourierCode(courierId, courierName, normalizedCourier);
  const parcelRules = await loadParcelRulesForCourier(
    supabaseAdmin,
    courierCode,
    normalizedCourier,
  );
  const isYalidine = normalizedCourier.includes("yalidine");
  const isEcotrack = normalizedCourier.includes("ecotrack");
  const isZrExpress = normalizedCourier.includes("zrexpress");
  const isGuepex = normalizedCourier.includes("guepex");
  const outboundCarrierCode = courierCode ||
    (isYalidine
      ? "yalidine"
      : isEcotrack
      ? "ecotrack"
      : isZrExpress
      ? "zrexpress"
      : isGuepex
      ? "guepex"
      : "generic");
  const outboundOwnerId = effectiveUserId || userId || "unknown";

  let trackingNumber = textValue(order.tracking_number);
  let labelUrl = textValue(order.label_url);
  let summary: Record<string, unknown> | undefined;

  if (isYalidine) {
    if (!selection) {
      return jsonResponse({ ok: false, message: "Missing shipment selection" }, 400);
    }
    const senderWilaya =
      textValue(pick(selection, "senderWilaya")) ||
      textValue(pick(selection, "from_wilaya_name")) ||
      "Alger";
    const receiverWilaya =
      textValue(pick(selection, "receiverWilaya")) ||
      textValue(pick(selection, "to_wilaya_name"));
    const receiverCommune =
      textValue(pick(selection, "receiverCommune")) ||
      textValue(pick(selection, "stopdeskCommune"));
    const firstName = textValue(pick(selection, "firstname"));
    const familyName = textValue(pick(selection, "familyname"));
    const phone =
      textValue(pick(selection, "phone_main")) ||
      textValue(pick(selection, "phone"));
    const address = textValue(pick(selection, "address"));
    const productList = textValue(pick(selection, "productList"));
    const price = numberValue(pick(selection, "price"), 0);
    const weight = intValue(pick(selection, "weight"), 1);
    const height = intValue(pick(selection, "height"), 0);
    const width = intValue(pick(selection, "width"), 0);
    const length = intValue(pick(selection, "length"), 0);
    const declaredValue = numberValue(pick(selection, "declaredValue"), price);
    const freeShipping =
      pick(selection, "freeshipping") === true ||
      textValue(pick(selection, "freeshipping")).toLowerCase() === "true";
    const insuranceActive =
      pick(selection, "insuranceActive") === true ||
      pick(selection, "insurance_active") === true;
    const isStopdesk =
      pick(selection, "deliveryType") === "stopdesk" ||
      pick(selection, "is_stopdesk") === true;
    const hasExchange = pick(selection, "hasExchange") === true;
    const orderRef =
      textValue(pick(selection, "order_ref")) || `${orderId}`;
    const validationError = validateParcelAgainstRules({
      rules: parcelRules,
      weightKg: weight,
      heightCm: height,
      widthCm: width,
      lengthCm: length,
      declaredValue,
      insuranceActive,
    });
    if (validationError) {
      return jsonResponse({ ok: false, ...validationError }, 400);
    }

    if (!senderWilaya || !receiverWilaya || !receiverCommune || !phone || !address) {
      return jsonResponse({ ok: false, message: "Missing receiver data" }, 400);
    }

    const payloadYalidine = [
      {
        order_id: orderRef,
        from_wilaya_name: senderWilaya,
        firstname: firstName,
        familyname: familyName,
        contact_phone: phone,
        address: address,
        to_commune_name: receiverCommune,
        to_wilaya_name: receiverWilaya,
        product_list: productList,
        price: Math.round(price),
        do_insurance: insuranceActive,
        declared_value: Math.round(declaredValue),
        height,
        width,
        length,
        weight: Math.round(weight),
        freeshipping: freeShipping,
        is_stopdesk: isStopdesk,
        has_exchange: hasExchange,
        stopdesk_id: isStopdesk ? numberValue(pick(selection, "stopdesk_id"), 0) || null : null,
      },
    ];
    const resp = await carrierFetch(
      supabaseUser,
      outboundCarrierCode,
      outboundOwnerId,
      "https://api.yalidine.app/v1/parcels/",
      {
      method: "POST",
      headers: {
        "X-API-ID": textValue(settingsRow?.api_key),
        "X-API-TOKEN": textValue(settingsRow?.api_secret),
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify(payloadYalidine),
      },
    );
    if (!resp) {
      return jsonResponse({ ok: false, message: "courier_rate_limited" }, 429);
    }
    if (!resp.ok) {
      return jsonResponse({ ok: false, message: `Yalidine ${resp.status}` }, 502);
    }
    const decoded = await resp.json();
    const data = decoded?.data ?? decoded;
    const first = Array.isArray(data)
      ? data[0]
      : data && typeof data === "object"
        ? data[Object.keys(data)[0]]
        : undefined;
    if (first?.success === false) {
      return jsonResponse({ ok: false, message: textValue(first?.message) }, 400);
    }
    trackingNumber = textValue(
      first?.tracking ?? first?.tracking_number ?? first?.tracking_id ?? first?.parcel_id,
    );
    const labelValue =
      first?.label ?? first?.label_url ?? first?.label_pdf ?? first?.labels;
    if (!trackingNumber) {
      return jsonResponse({ ok: false, message: "Tracking missing" }, 500);
    }
    if (labelValue) {
      const bytes = await loadLabelBytes(textValue(labelValue));
      labelUrl = await uploadLabel(
        supabaseAdmin,
        outboundOwnerId,
        `yalidine-${orderId}.pdf`,
        bytes,
      );
    } else {
      labelUrl = "";
    }
    summary = {
      delivery_fee: first?.delivery_fee,
      taxe_percentage: first?.taxe_percentage,
      taxe_retour: first?.taxe_retour,
      price: first?.price ?? price,
      declared_value: first?.declared_value ?? declaredValue,
      tracking: trackingNumber,
      label_url: labelUrl,
    };
  } else if (isGuepex) {
    if (!selection) {
      return jsonResponse({ ok: false, message: "Missing shipment selection" }, 400);
    }
    if (!settingsRow.api_secret) {
      return jsonResponse({ ok: false, message: "Missing courier token" }, 400);
    }

    const senderWilaya =
      textValue(pick(selection, "senderWilaya")) ||
      textValue(pick(selection, "from_wilaya_name")) ||
      "Alger";
    const receiverWilaya =
      textValue(pick(selection, "receiverWilaya")) ||
      textValue(pick(selection, "to_wilaya_name"));
    const receiverCommune =
      textValue(pick(selection, "receiverCommune")) ||
      textValue(pick(selection, "stopdeskCommune")) ||
      textValue(pick(selection, "to_commune_name"));
    const firstName = textValue(pick(selection, "firstname"));
    const familyName = textValue(pick(selection, "familyname"));
    const phone =
      textValue(pick(selection, "phone_main")) ||
      textValue(pick(selection, "phone"));
    const address = textValue(pick(selection, "address"));
    const productList = textValue(pick(selection, "productList"));
    const price = numberValue(pick(selection, "price"), 0);
    const weight = intValue(pick(selection, "weight"), 1);
    const height = intValue(pick(selection, "height"), 0);
    const width = intValue(pick(selection, "width"), 0);
    const length = intValue(pick(selection, "length"), 0);
    const declaredValue = numberValue(pick(selection, "declaredValue"), price);
    const freeShipping =
      pick(selection, "freeshipping") === true ||
      textValue(pick(selection, "freeshipping")).toLowerCase() === "true";
    const insuranceActive =
      pick(selection, "insuranceActive") === true ||
      pick(selection, "insurance_active") === true;
    const isStopdesk =
      pick(selection, "deliveryType") === "stopdesk" ||
      pick(selection, "is_stopdesk") === true;
    const stopdeskId =
      textValue(pick(selection, "stopdesk_id")) ||
      textValue(pick(selection, "stopdeskId"));
    const hasExchange = pick(selection, "hasExchange") === true;
    const productToCollect = textValue(
      pick(selection, "product_to_collect") || pick(selection, "productToCollect"),
    );
    const orderRef =
      textValue(pick(selection, "order_ref")) || `${orderId}`;

    const validationError = validateParcelAgainstRules({
      rules: parcelRules,
      weightKg: weight,
      heightCm: height,
      widthCm: width,
      lengthCm: length,
      declaredValue,
      insuranceActive,
    });
    if (validationError) {
      return jsonResponse({ ok: false, ...validationError }, 400);
    }

    if (!senderWilaya || !receiverWilaya || !receiverCommune || !phone || !address) {
      return jsonResponse({ ok: false, message: "Missing receiver data" }, 400);
    }
    if (isStopdesk && !stopdeskId) {
      return jsonResponse({ ok: false, message: "Missing pickup point" }, 400);
    }

    const guepexPayload: Record<string, unknown> = {
      order_id: orderRef,
      from_wilaya_name: senderWilaya,
      firstname: firstName,
      familyname: familyName,
      contact_phone: phone,
      address,
      to_commune_name: receiverCommune,
      to_wilaya_name: receiverWilaya,
      product_list: productList,
      price: Math.round(price),
      do_insurance: insuranceActive,
      declared_value: Math.round(declaredValue),
      height,
      width,
      length,
      weight: Math.round(weight),
      freeshipping: freeShipping,
      is_stopdesk: isStopdesk,
      has_exchange: hasExchange,
    };
    if (isStopdesk) {
      guepexPayload.stopdesk_id = stopdeskId;
    }
    if (hasExchange && productToCollect) {
      guepexPayload.product_to_collect = productToCollect;
    }

    const url = `${guepexBaseUrl()}/v1/parcels`;
    const headers = {
      "X-API-ID": textValue(settingsRow?.api_key),
      "X-API-TOKEN": textValue(settingsRow?.api_secret),
      "Content-Type": "application/json",
      Accept: "application/json",
    };
    let resp = await carrierFetch(
      supabaseUser,
      outboundCarrierCode,
      outboundOwnerId,
      url,
      {
        method: "POST",
        headers,
        body: JSON.stringify(guepexPayload),
      },
    );
    if (!resp) {
      return jsonResponse({ ok: false, message: "courier_rate_limited" }, 429);
    }
    if (!resp.ok) {
      // Fallback: some carriers accept list payloads for bulk create.
      resp = await carrierFetch(
        supabaseUser,
        outboundCarrierCode,
        outboundOwnerId,
        url,
        {
          method: "POST",
          headers,
          body: JSON.stringify([guepexPayload]),
        },
      );
      if (!resp) {
        return jsonResponse({ ok: false, message: "courier_rate_limited" }, 429);
      }
    }
    if (!resp.ok) {
      const bodyText = await resp.text();
      return jsonResponse(
        { ok: false, message: `Guepex ${resp.status}: ${bodyText}` },
        502,
      );
    }

    const decoded = await resp.json();
    const data = decoded?.data ?? decoded?.items ?? decoded?.results ?? decoded;
    const pickGuepexRecord = (value: unknown): Record<string, unknown> | undefined => {
      if (Array.isArray(value)) {
        const firstArrayItem = value[0];
        return firstArrayItem && typeof firstArrayItem === "object"
          ? firstArrayItem as Record<string, unknown>
          : undefined;
      }
      if (!value || typeof value !== "object") return undefined;
      const obj = value as Record<string, unknown>;
      if (
        "success" in obj ||
        "tracking" in obj ||
        "tracking_number" in obj ||
        "tracking_id" in obj ||
        "parcel_id" in obj
      ) {
        return obj;
      }
      const keys = Object.keys(obj);
      for (const key of keys) {
        const nested = obj[key];
        if (!nested || typeof nested !== "object") continue;
        const nestedObj = nested as Record<string, unknown>;
        if (
          "success" in nestedObj ||
          "tracking" in nestedObj ||
          "tracking_number" in nestedObj ||
          "tracking_id" in nestedObj ||
          "parcel_id" in nestedObj
        ) {
          return nestedObj;
        }
      }
      if (keys.length === 1) {
        const nested = obj[keys[0]];
        if (nested && typeof nested === "object") {
          return nested as Record<string, unknown>;
        }
      }
      return undefined;
    };
    const first = pickGuepexRecord(data) ?? pickGuepexRecord(decoded);
    if (!first) {
      return jsonResponse({ ok: false, message: "Unexpected Guepex response" }, 502);
    }
    if (first?.success === false) {
      return jsonResponse({ ok: false, message: textValue(first?.message) }, 400);
    }

    trackingNumber = textValue(
      first?.tracking ?? first?.tracking_number ?? first?.tracking_id ?? first?.parcel_id,
    );
    let labelValue =
      first?.label ?? first?.label_url ?? first?.label_pdf ?? first?.labels;
    if (!trackingNumber) {
      const lookupUrl = `${guepexBaseUrl()}/v1/parcels?order_id=${encodeURIComponent(orderRef)}&page_size=1`;
      const lookupResp = await carrierFetch(
        supabaseUser,
        outboundCarrierCode,
        outboundOwnerId,
        lookupUrl,
        { method: "GET", headers },
      );
      if (!lookupResp) {
        return jsonResponse({ ok: false, message: "courier_rate_limited" }, 429);
      }
      if (lookupResp.ok) {
        const lookupDecoded = await lookupResp.json();
        const lookupData =
          lookupDecoded?.data ??
          lookupDecoded?.items ??
          lookupDecoded?.results ??
          lookupDecoded;
        const lookupFirst = pickGuepexRecord(lookupData) ?? pickGuepexRecord(lookupDecoded);
        if (lookupFirst) {
          trackingNumber = textValue(
            lookupFirst?.tracking ??
              lookupFirst?.tracking_number ??
              lookupFirst?.tracking_id ??
              lookupFirst?.parcel_id,
          );
          if (!labelValue) {
            labelValue =
              lookupFirst?.label ??
              lookupFirst?.label_url ??
              lookupFirst?.label_pdf ??
              lookupFirst?.labels;
          }
        }
      }
    }
    if (!trackingNumber) {
      return jsonResponse({ ok: false, message: "Tracking missing" }, 500);
    }
    if (labelValue) {
      const bytes = await loadLabelBytes(textValue(labelValue));
      labelUrl = await uploadLabel(
        supabaseAdmin,
        outboundOwnerId,
        `guepex-${orderId}.pdf`,
        bytes,
      );
    } else {
      labelUrl = "";
    }

    summary = {
      price: first?.price ?? price,
      declared_value: first?.declared_value ?? declaredValue,
      tracking: trackingNumber,
      label_url: labelUrl,
    };
  } else if (isEcotrack) {
    if (!selection) {
      return jsonResponse({ ok: false, message: "Missing shipment selection" }, 400);
    }
      const price = numberValue(pick(selection, "price"), 0);
      const weight = intValue(pick(selection, "weight"), 1);
      const height = intValue(pick(selection, "height"), 0);
      const width = intValue(pick(selection, "width"), 0);
      const length = intValue(pick(selection, "length"), 0);
      const declaredValue = numberValue(
        pick(selection, "declaredValue"),
        price,
      );
      const insuranceActive =
        pick(selection, "insuranceActive") === true ||
        pick(selection, "insurance_active") === true;
      const validationError = validateParcelAgainstRules({
        rules: parcelRules,
        weightKg: weight,
        heightCm: height,
        widthCm: width,
        lengthCm: length,
        declaredValue,
        insuranceActive,
      });
      if (validationError) {
        return jsonResponse({ ok: false, ...validationError }, 400);
      }
      const orderPayload: Record<string, string> = {
      reference: orderId,
      nom_client: `${textValue(pick(selection, "familyname"))} ${textValue(pick(selection, "firstname"))}`.trim(),
      telephone:
        textValue(pick(selection, "phone_main")) || textValue(pick(selection, "phone")),
      telephone_2: textValue(pick(selection, "phone_secondary")),
      adresse: textValue(pick(selection, "address")),
      code_postal: textValue(pick(selection, "zip")),
      commune: textValue(pick(selection, "receiverCommune")),
      code_wilaya: textValue(pick(selection, "wilayaCode")),
      montant: textValue(pick(selection, "price")),
      remarque: textValue(pick(selection, "remark")),
      produit: textValue(pick(selection, "productList")),
      boutique: textValue(pick(selection, "shopName")),
      type: pick(selection, "hasExchange") === true ? "2" : "1",
        stop_desk: pick(selection, "deliveryType") === "stopdesk" ? "1" : "0",
        weight: `${weight}`,
      };
      const params = new URLSearchParams(orderPayload);
      const baseUrls = ecotrackBaseUrls();
      let resp: Response | null = null;
      let errorBody = "";
      for (const base of baseUrls) {
        const url = `${joinUrl(base, "/api/v1/create/order")}?${params.toString()}`;
        resp = await carrierFetch(
          supabaseUser,
          outboundCarrierCode,
          outboundOwnerId,
          url,
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${textValue(settingsRow?.api_key)}`,
              Accept: "application/json",
            },
          },
        );
        if (!resp) {
          return jsonResponse({ ok: false, message: "courier_rate_limited" }, 429);
        }
        if (resp.ok) break;
        try {
          errorBody = await resp.text();
        } catch {
          errorBody = "";
        }
        if (resp.status !== 404 && resp.status !== 405) break;
      }
      if (!resp || !resp.ok) {
        const suffix = errorBody ? `: ${errorBody}` : "";
        return jsonResponse(
          { ok: false, message: `Ecotrack ${resp?.status ?? "error"}${suffix}` },
          502,
        );
      }
      const decoded = await resp.json();
      const results = decoded?.results ?? {};
      const result = results?.[orderId] ?? decoded;
      if (result?.success === false) {
        return jsonResponse({ ok: false, message: textValue(result?.message) }, 400);
      }
      trackingNumber = textValue(result?.tracking ?? decoded?.tracking);
      if (!trackingNumber) {
        return jsonResponse({ ok: false, message: "Tracking missing" }, 500);
      }
      const labelUrls = baseUrls.length ? baseUrls : ecotrackBaseUrls();
      let labelResp: Response | null = null;
      let labelError = "";
      for (const base of labelUrls) {
        const labelUrlCandidate = `${joinUrl(base, "/api/v1/get/order/label")}?tracking=${encodeURIComponent(trackingNumber)}`;
        labelResp = await carrierFetch(
          supabaseUser,
          outboundCarrierCode,
          outboundOwnerId,
          labelUrlCandidate,
          {
            method: "GET",
            headers: {
              Authorization: `Bearer ${textValue(settingsRow?.api_key)}`,
              Accept: "application/pdf,application/json",
            },
          },
        );
        if (!labelResp) {
          return jsonResponse({ ok: false, message: "courier_rate_limited" }, 429);
        }
        if (labelResp.ok) break;
        try {
          labelError = await labelResp.text();
        } catch {
          labelError = "";
        }
        if (labelResp.status !== 404 && labelResp.status !== 405) break;
      }
      if (!labelResp || !labelResp.ok) {
        const suffix = labelError ? `: ${labelError}` : "";
        return jsonResponse(
          { ok: false, message: `Label ${labelResp?.status ?? "error"}${suffix}` },
          502,
        );
      }
      const contentType = labelResp.headers.get("content-type") ?? "";
      let bytes: Uint8Array | null = null;
    if (contentType.includes("application/pdf")) {
      bytes = new Uint8Array(await labelResp.arrayBuffer());
    } else {
      const bodyText = await labelResp.text();
      if (bodyText.trim().startsWith("http")) {
        bytes = await loadLabelBytes(bodyText.trim());
      } else {
        try {
          const parsed = JSON.parse(bodyText);
          if (parsed?.label) bytes = await loadLabelBytes(textValue(parsed.label));
        } catch {
          bytes = null;
        }
      }
    }
    if (bytes) {
      labelUrl = await uploadLabel(
        supabaseAdmin,
        outboundOwnerId,
        `ecotrack-${trackingNumber}.pdf`,
        bytes,
      );
    } else {
      labelUrl = "";
    }
  } else if (isZrExpress) {
    if (!selection) {
      return jsonResponse({ ok: false, message: "Missing shipment selection" }, 400);
    }
    if (!settingsRow.api_secret) {
      return jsonResponse({ ok: false, message: "Missing courier tenant" }, 400);
    }

    const normalizePhone = (value: string) => {
      const raw = value.trim();
      if (!raw) return "";
      let cleaned = raw.replace(/[^\d+]/g, "");
      if (cleaned.startsWith("00")) {
        cleaned = `+${cleaned.slice(2)}`;
      }
      if (cleaned.startsWith("+")) {
        const digits = cleaned.slice(1).replace(/\D/g, "");
        if (digits.startsWith("2130")) {
          const fixed = `213${digits.slice(4)}`;
          if (fixed.length < 8) return "";
          return `+${fixed}`;
        }
        if (digits.length < 8) return "";
        return `+${digits}`;
      }
      let digits = cleaned.replace(/\D/g, "");
      if (!digits) return "";
      if (digits.startsWith("213")) {
        digits = digits.slice(3);
      }
      if (digits.startsWith("0")) {
        digits = digits.slice(1);
      }
      if (digits.length < 8) return "";
      if (digits.length > 9) {
        digits = digits.slice(-9);
      }
      return `+213${digits}`;
    };

    const isUuid = (value: string) =>
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
        .test(value);

    const normalizeName = (value: string) =>
      textValue(value)
        .toLowerCase()
        .normalize("NFKD")
        .replace(/[\u0300-\u036f]/g, "")
        .replace(/[^a-z0-9]+/g, "");

    const resolveZrWilayaId = async (
      wilayaId: string,
      wilayaName: string,
    ) => {
      const code = textValue(wilayaId);
      const nameKey = normalizeName(wilayaName);
      if (!code && !nameKey) return "";
      const { data } = await supabaseAdmin
        .from("courier_locations")
        .select("remote_id,wilaya_code,name_norm")
        .eq("courier_key", "zrexpress")
        .eq("type", "wilaya");
      if (!data || !data.length) return "";
      const byCode = data.find((r) =>
        textValue(r.remote_id) === code || textValue(r.wilaya_code) === code
      );
      if (byCode) return textValue(byCode.remote_id);
      const byName = data.find((r) => textValue(r.name_norm) === nameKey);
      return byName ? textValue(byName.remote_id) : "";
    };

    const resolveZrCommuneId = async (
      wilayaRemoteId: string,
      communeId: string,
      communeName: string,
    ) => {
      const nameKey = normalizeName(communeName);
      if (!wilayaRemoteId || (!communeId && !nameKey)) return "";
      const { data } = await supabaseAdmin
        .from("courier_locations")
        .select("remote_id,parent_remote_id,name_norm")
        .eq("courier_key", "zrexpress")
        .eq("type", "commune")
        .eq("parent_remote_id", wilayaRemoteId);
      if (!data || !data.length) return "";
      const byId = data.find((r) => textValue(r.remote_id) === communeId);
      if (byId) return textValue(byId.remote_id);
      const byName = data.find((r) => textValue(r.name_norm) === nameKey);
      return byName ? textValue(byName.remote_id) : "";
    };

    let receiverWilayaId =
      textValue(pick(selection, "receiverWilayaId")) ||
      textValue(pick(selection, "wilayaCode"));
    let receiverCommuneId =
      textValue(pick(selection, "receiverCommuneId")) ||
      textValue(pick(selection, "commune_id")) ||
      textValue(pick(selection, "receiver_commune_id"));
    const receiverWilayaName =
      textValue(pick(selection, "receiverWilaya")) ||
      textValue(pick(selection, "to_wilaya_name"));
    const receiverCommuneName =
      textValue(pick(selection, "receiverCommune")) ||
      textValue(pick(selection, "to_commune_name"));
    const isStopdesk =
      pick(selection, "deliveryType") === "stopdesk" ||
      pick(selection, "is_stopdesk") === true;
    const hubId =
      textValue(pick(selection, "stopdesk_id")) ||
      textValue(pick(selection, "stopdeskId")) ||
      textValue(pick(selection, "hubId"));

    const phoneRaw =
      textValue(pick(selection, "phone_e164")) ||
      textValue(pick(selection, "phone_main")) ||
      textValue(pick(selection, "contact_phone")) ||
      textValue(pick(selection, "phone"));
    const primaryPhone =
      phoneRaw.split(/[,;/\s]+/).filter(Boolean)[0] ?? phoneRaw;
    const normalizedPhone = normalizePhone(primaryPhone);
    const phone2Raw =
      textValue(pick(selection, "phone2_e164")) ||
      textValue(pick(selection, "phone_secondary")) ||
      textValue(pick(selection, "phone2"));
    const normalizedPhone2 = phone2Raw ? normalizePhone(phone2Raw) : "";
    const customerName = `${textValue(pick(selection, "familyname"))} ${textValue(
      pick(selection, "firstname"),
    )}`.trim();
    const address = textValue(pick(selection, "address"));
    const productList = textValue(pick(selection, "productList"));
    const price = numberValue(pick(selection, "price"), 0);
    const weight = intValue(pick(selection, "weight"), 1);
    const height = intValue(pick(selection, "height"), 0);
    const width = intValue(pick(selection, "width"), 0);
    const length = intValue(pick(selection, "length"), 0);
    const declaredValue = numberValue(pick(selection, "declaredValue"), price);
    const insuranceActive =
      pick(selection, "insuranceActive") === true ||
      pick(selection, "insurance_active") === true;
    const validationError = validateParcelAgainstRules({
      rules: parcelRules,
      weightKg: weight,
      heightCm: height,
      widthCm: width,
      lengthCm: length,
      declaredValue,
      insuranceActive,
    });
    if (validationError) {
      return jsonResponse({ ok: false, ...validationError }, 400);
    }

    if (
      !receiverWilayaId ||
      !receiverCommuneId ||
      !customerName ||
      !normalizedPhone ||
      !address
    ) {
      return jsonResponse({ ok: false, message: "Missing receiver data" }, 400);
    }
    if (!normalizedPhone) {
      return jsonResponse({ ok: false, message: "Invalid phone format" }, 400);
    }
    if (phone2Raw && !normalizedPhone2) {
      return jsonResponse({ ok: false, message: "Invalid phone2 format" }, 400);
    }
    const dzNational = (value: string) =>
      value.replace(/^\+?213/, "");
    const isZrMobile = (value: string) => {
      const national = dzNational(value);
      return national.startsWith("5") || national.startsWith("6");
    };
    if (!isZrMobile(normalizedPhone)) {
      return jsonResponse({ ok: false, message: "zr_phone_invalid" }, 400);
    }
    if (normalizedPhone2 && !isZrMobile(normalizedPhone2)) {
      return jsonResponse({ ok: false, message: "zr_phone_invalid" }, 400);
    }
    if (!isUuid(receiverWilayaId)) {
      receiverWilayaId = await resolveZrWilayaId(
        receiverWilayaId,
        receiverWilayaName,
      );
    }
    if (!isUuid(receiverCommuneId)) {
      receiverCommuneId = await resolveZrCommuneId(
        receiverWilayaId,
        receiverCommuneId,
        receiverCommuneName,
      );
    }
    if (!isUuid(receiverWilayaId) || !isUuid(receiverCommuneId)) {
      return jsonResponse({ ok: false, message: "invalid_territory_id" }, 400);
    }
    if (isStopdesk && !hubId) {
      return jsonResponse({ ok: false, message: "Missing pickup point" }, 400);
    }

    const headers = {
      "X-Api-Key": textValue(settingsRow.api_key),
      "X-Tenant": textValue(settingsRow.api_secret),
      "Content-Type": "application/json",
      Accept: "application/json",
    };

    const productGuid = crypto.randomUUID();
    const productSku = textValue(selection.product_sku ?? selection.productSku ?? orderId);
    const cityName = receiverWilayaName;
    const districtName = receiverCommuneName;
    const postalCode = textValue(pick(selection, "zip"));
    const orderedProduct: Record<string, unknown> = {
      productId: productGuid,
      productSku: productSku || `SKU-${orderId}`,
      productName: productList || `Order ${orderId}`,
      unitPrice: Math.round(price),
      quantity: 1,
      stockType: "local",
    };
    if (length > 0) orderedProduct.length = Math.round(length);
    if (width > 0) orderedProduct.width = Math.round(width);
    if (height > 0) orderedProduct.height = Math.round(height);
    if (weight > 0) orderedProduct.weight = Math.round(weight);

    const phonePayload: Record<string, unknown> = {
      number1: normalizedPhone,
      number2: normalizedPhone2 || normalizedPhone,
    };

    const payloadZr: Record<string, unknown> = {
      customer: {
        customerId: textValue(order.buyer_id) || orderId,
        name: customerName,
        phone: phonePayload,
      },
      deliveryAddress: {
        street: address,
        city: cityName,
        district: districtName,
        postalCode: postalCode,
        country: "algeria",
        cityTerritoryId: receiverWilayaId,
        districtTerritoryId: receiverCommuneId,
      },
      orderedProducts: [orderedProduct],
      amount: Math.round(price),
      description: productList || `Order ${orderId}`,
      deliveryType: isStopdesk ? "pickup-point" : "home",
    };
    if (isStopdesk && hubId) {
      payloadZr.hubId = hubId;
    }

    const resp = await carrierFetch(
      supabaseUser,
      outboundCarrierCode,
      outboundOwnerId,
      "https://api.zrexpress.app/api/v1/parcels",
      {
        method: "POST",
        headers,
        body: JSON.stringify(payloadZr),
      },
    );
    if (!resp) {
      return jsonResponse({ ok: false, message: "courier_rate_limited" }, 429);
    }
    if (!resp.ok) {
      let bodyText = "";
      try {
        bodyText = await resp.text();
      } catch {
        bodyText = "";
      }
      return jsonResponse(
        { ok: false, message: `ZrExpress ${resp.status}: ${bodyText}` },
        502,
      );
    }
    const decoded = await resp.json();
    const parcel =
      decoded?.data ??
      decoded?.item ??
      decoded?.result ??
      decoded?.parcel ??
      decoded;
    const createdId = textValue(
      parcel?.id ??
        parcel?.parcelId ??
        parcel?.parcel_id ??
        parcel?.code ??
        parcel?.barcode,
    );
    trackingNumber = textValue(
      parcel?.trackingNumber ??
        parcel?.tracking ??
        parcel?.tracking_number ??
        parcel?.barcode ??
        parcel?.code,
    );
    if (!trackingNumber && createdId) {
      const detailResp = await carrierFetch(
        supabaseUser,
        outboundCarrierCode,
        outboundOwnerId,
        `https://api.zrexpress.app/api/v1/parcels/${createdId}`,
        { method: "GET", headers },
      );
      if (!detailResp) {
        return jsonResponse({ ok: false, message: "courier_rate_limited" }, 429);
      }
      if (detailResp.ok) {
        const detail = await detailResp.json();
        trackingNumber = textValue(
          detail?.trackingNumber ??
            detail?.tracking ??
            detail?.tracking_number ??
            detail?.barcode ??
            detail?.code,
        );
      }
    }
    if (!trackingNumber) {
      return jsonResponse({ ok: false, message: "Tracking missing" }, 500);
    }

    const labelResp = await carrierFetch(
      supabaseUser,
      outboundCarrierCode,
      outboundOwnerId,
      "https://api.zrexpress.app/api/v1/parcels/labels/individual/pdf",
      {
        method: "POST",
        headers,
        body: JSON.stringify({ trackingNumbers: [trackingNumber] }),
      },
    );
    if (!labelResp) {
      return jsonResponse({ ok: false, message: "courier_rate_limited" }, 429);
    }
    if (!labelResp.ok) {
      const bodyText = await labelResp.text();
      return jsonResponse(
        { ok: false, message: `Label ${labelResp.status}: ${bodyText}` },
        502,
      );
    }
    const extractLabelSource = (value: unknown) => textValue(value ?? "");
    const looksLikeLabel = (value: string) => {
      const trimmed = value.trim();
      if (!trimmed) return false;
      if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) return true;
      if (/^data:.*;base64,/i.test(trimmed)) return true;
      if (/^[A-Za-z0-9+/=]+$/.test(trimmed) && trimmed.length > 200) return true;
      return false;
    };
    const pickLabelValue = (obj: Record<string, unknown> | undefined) => {
      if (!obj) return "";
      return extractLabelSource(
        obj.url ??
          obj.labelUrl ??
          obj.label_url ??
          obj.pdfUrl ??
          obj.pdf_url ??
          obj.fileUrl ??
          obj.file_url ??
          obj.downloadUrl ??
          obj.download_url ??
          obj.link ??
          obj.label ??
          obj.file ??
          obj.pdf ??
          obj.base64 ??
          obj.content ??
          obj.fileBase64 ??
          obj.file_base64 ??
          obj.contentBase64 ??
          obj.content_base64 ??
          obj.pdfBase64 ??
          obj.pdf_base64,
      );
    };
    const deepFindLabel = (value: unknown): string => {
      if (value == null) return "";
      if (typeof value === "string") {
        return looksLikeLabel(value) ? value : "";
      }
      if (Array.isArray(value)) {
        for (const item of value) {
          const found = deepFindLabel(item);
          if (found) return found;
        }
        return "";
      }
      if (typeof value === "object") {
        const obj = value as Record<string, unknown>;
        const direct = pickLabelValue(obj);
        if (looksLikeLabel(direct)) return direct;
        for (const [key, val] of Object.entries(obj)) {
          const keyLower = key.toLowerCase();
          if (
            keyLower.includes("label") ||
            keyLower.includes("pdf") ||
            keyLower.includes("url") ||
            keyLower.includes("file") ||
            keyLower.includes("download") ||
            keyLower.includes("link")
          ) {
            const candidate = deepFindLabel(val);
            if (candidate) return candidate;
          }
        }
        for (const val of Object.values(obj)) {
          const candidate = deepFindLabel(val);
          if (candidate) return candidate;
        }
      }
      return "";
    };
    const parseLabelResponse = async (resp: Response) => {
      const bytes = new Uint8Array(await resp.arrayBuffer());
      if (isPdfBytes(bytes)) {
        return { labelBytes: bytes, labelUrl: "" };
      }
      const bodyText = decodeBytes(bytes);
      let labelSource = "";
      if (!bodyText) return { labelBytes: null, labelUrl: "" };
      try {
        const labelDecoded = JSON.parse(bodyText);
        const labelData =
          labelDecoded?.data ??
          labelDecoded?.items ??
          labelDecoded?.results ??
          labelDecoded?.labels ??
          labelDecoded?.successes ??
          labelDecoded;
        if (Array.isArray(labelData)) {
          const match = labelData.find((m) =>
            textValue(m?.trackingNumber ?? m?.tracking ?? m?.number) === trackingNumber
          );
          labelSource =
            deepFindLabel(match) ||
            deepFindLabel(labelData) ||
            deepFindLabel(labelDecoded);
        } else if (labelData && typeof labelData === "object") {
          labelSource = deepFindLabel(labelData as Record<string, unknown>);
        } else {
          labelSource = deepFindLabel(labelDecoded);
        }
      } catch {
        labelSource = deepFindLabel(bodyText) || extractLabelSource(bodyText);
      }
      if (!labelSource) return { labelBytes: null, labelUrl: "" };
      if (labelSource.startsWith("http://") || labelSource.startsWith("https://")) {
        return { labelBytes: null, labelUrl: labelSource };
      }
      const labelBytes = await loadLabelBytes(labelSource);
      return { labelBytes, labelUrl: "" };
    };

    let labelBytes: Uint8Array | null = null;
    let labelLink = "";
    {
      const parsed = await parseLabelResponse(labelResp);
      labelBytes = parsed.labelBytes;
      labelLink = parsed.labelUrl;
    }
    if (!labelBytes && !labelLink) {
      const htmlResp = await carrierFetch(
        supabaseUser,
        outboundCarrierCode,
        outboundOwnerId,
        "https://api.zrexpress.app/api/v1/parcels/labels/individual",
        {
          method: "POST",
          headers,
          body: JSON.stringify({ trackingNumbers: [trackingNumber] }),
        },
      );
      if (!htmlResp) {
        return jsonResponse({ ok: false, message: "courier_rate_limited" }, 429);
      }
      if (htmlResp.ok) {
        const parsed = await parseLabelResponse(htmlResp);
        labelBytes = parsed.labelBytes;
        labelLink = parsed.labelUrl;
      } else {
        const bodyText = await htmlResp.text();
        return jsonResponse(
          { ok: false, message: `Label ${htmlResp.status}: ${bodyText}` },
          502,
        );
      }
    }
    if (!labelBytes && !labelLink) {
      return jsonResponse({ ok: false, message: "Label missing" }, 502);
    }
    if (labelBytes) {
      labelUrl = await uploadLabel(
        supabaseAdmin,
        outboundOwnerId,
        `zrexpress-${trackingNumber}.pdf`,
        labelBytes,
      );
    } else {
      labelUrl = labelLink;
    }
    summary = {
      price: price,
      tracking: trackingNumber,
      label_url: labelUrl,
    };
  }

  const shipmentPayload: Record<string, unknown> = {
    order_id: orderId,
    tracking_number: trackingNumber || null,
    label_url: labelUrl || null,
    status: labelUrl ? "shipped" : "pending",
  };

  let shipmentError: { message?: string; code?: string } | null = null;
  let shipmentPayloadCurrent = { ...shipmentPayload };
  for (let attempt = 0; attempt < 3; attempt++) {
    const res = await supabaseAdmin
      .from("shipments")
      .upsert(shipmentPayloadCurrent, { onConflict: "order_id" });
    shipmentError = res.error ?? null;
    if (!shipmentError) break;
    const message = shipmentError.message ?? "";
    const match = message.match(/Could not find the '([^']+)' column/);
    if (match?.[1]) {
      delete shipmentPayloadCurrent[match[1]];
      continue;
    }
    if (shipmentError.code === "42703") {
      delete shipmentPayloadCurrent.carrier;
      continue;
    }
    break;
  }
  if (shipmentError) {
    return jsonResponse(
      { ok: false, message: shipmentError.message },
      500,
    );
  }
  const orderUpdate: Record<string, unknown> = {
    courier_id: courierId || order.courier_id,
    courier_name: courierName || order.courier_name,
    delivery_method: deliveryMode || order.delivery_method,
    shipping_cost: shippingCost ?? order.shipping_cost,
    tracking_number: trackingNumber || order.tracking_number,
    label_url: labelUrl || order.label_url,
  };
  if (labelUrl) {
    orderUpdate.status = "shipped";
  }
  const { error: orderUpdateError } = await supabaseAdmin
    .from("orders")
    .update(orderUpdate)
    .eq("id", orderId);
  if (orderUpdateError) {
    return jsonResponse(
      { ok: false, message: orderUpdateError.message },
      500,
    );
  }

  const statusValue = labelUrl ? "shipped" : "validated";
  const i18nKey = labelUrl
    ? "order.system.shipped"
    : "order.system.validated";
  const eventPayload: Record<string, unknown> = {
    i18n_key: i18nKey,
    status: statusValue,
    status_i18n: `order.status.${statusValue}`,
    tracking_number: trackingNumber || null,
    label_url: labelUrl || null,
    courier_name: courierName || courierId,
  };
  const eventKey = labelUrl
    ? `order:${orderId}:shipped`
    : `order:${orderId}:validated`;
  try {
    await supabaseAdmin.rpc("post_order_event", {
      p_order_id: Number(orderId),
      p_event: labelUrl ? "order_shipped" : "order_validated",
      p_payload: eventPayload,
      p_dedupe_key: eventKey,
    });
  } catch (_) {
    // Ignore chat event errors; shipment generation should still succeed.
  }

  await supabaseUser.rpc("log_audit", {
    p_actor_id: effectiveUserId,
    p_action: "create_shipment",
    p_entity: "orders",
    p_entity_id: orderId,
    p_details: {
      courier_id: courierId,
      courier_name: courierName,
      tracking_number: trackingNumber,
      label_url: labelUrl,
      async: false,
    },
  });

  return jsonResponse({
    ok: true,
    tracking_number: trackingNumber,
    label_url: labelUrl,
    summary,
  });
});
