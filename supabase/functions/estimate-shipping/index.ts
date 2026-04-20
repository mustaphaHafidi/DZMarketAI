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

const numberValue = (value: unknown) => {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  const parsed = Number(textValue(value).replace(",", "."));
  return Number.isFinite(parsed) ? parsed : null;
};

const normalizeToken = (value: unknown) =>
  textValue(value)
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "");

const normalizeCourier = (value: unknown) =>
  textValue(value).toLowerCase().replace(/[^a-z0-9]/g, "");

const ecotrackBaseUrls = () => {
  const candidates = ["https://api.ecotrack.dz", "https://ovred.ecotrack.dz"];
  const seen = new Set<string>();
  return candidates.filter((value) => {
    const normalized = value.replace(/\/+$/, "");
    if (!normalized || seen.has(normalized)) return false;
    seen.add(normalized);
    return true;
  });
};

const extractList = (decoded: unknown): Array<Record<string, unknown>> => {
  if (Array.isArray(decoded)) {
    return decoded.filter((item): item is Record<string, unknown> =>
      !!item && typeof item === "object"
    );
  }
  if (decoded && typeof decoded === "object") {
    const obj = decoded as Record<string, unknown>;
    const direct = [obj.data, obj.results, obj.items, obj.livraison];
    for (const candidate of direct) {
      if (Array.isArray(candidate)) {
        return candidate.filter((item): item is Record<string, unknown> =>
          !!item && typeof item === "object"
        );
      }
    }
    if (obj.data && typeof obj.data === "object") {
      const nested = obj.data as Record<string, unknown>;
      const nestedCandidates = [nested.items, nested.results, nested.livraison];
      for (const candidate of nestedCandidates) {
        if (Array.isArray(candidate)) {
          return candidate.filter((item): item is Record<string, unknown> =>
            !!item && typeof item === "object"
          );
        }
      }
    }
  }
  return [];
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
      const backoff = Math.min(320 * 2 ** (attempt - 1), 5000);
      await sleep((retryAfterMs ?? backoff) + jitter);
    } catch (error) {
      lastError = error;
      if (attempt === maxAttempts) break;
      const jitter = Math.floor(Math.random() * 120);
      const backoff = Math.min(320 * 2 ** (attempt - 1), 5000);
      await sleep(backoff + jitter);
    }
  }
  throw lastError instanceof Error ? lastError : new Error("network_retry_failed");
};

type CarrierRateWindow = { limit: number; seconds: number };

const quoteRatePolicy = (carrierCode: string): CarrierRateWindow[] => {
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
      return [{ limit: 5, seconds: 1 }, { limit: 60, seconds: 60 }];
  }
};

const enforceCarrierRateLimit = async (
  supabase: ReturnType<typeof createClient>,
  carrierCode: string,
  sellerId: string,
) => {
  for (const window of quoteRatePolicy(carrierCode)) {
    const ok = await consumeRateLimit(
      supabase,
      `carrier_quote:${carrierCode}:${sellerId}:${window.seconds}`,
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
  sellerId: string,
  url: string,
  init: RequestInit,
) => {
  const allowed = await enforceCarrierRateLimit(supabase, carrierCode, sellerId);
  if (!allowed) return null;
  return fetchWithRetry(url, init);
};

const pickNumber = (record: Record<string, unknown>, keys: string[]) => {
  for (const key of keys) {
    if (!(key in record)) continue;
    const parsed = numberValue(record[key]);
    if (parsed != null) return parsed;
  }
  return null;
};

const firstLikelyPrice = (record: Record<string, unknown>) => {
  const ignored = [
    "id",
    "code",
    "min",
    "max",
    "wilaya",
    "commune",
    "retour",
    "day",
    "days",
    "hour",
    "hours",
    "delay",
    "delai",
    "eta",
    "kg",
    "weight",
    "poids",
    "zone",
    "distance",
    "lat",
    "lng",
    "long",
    "name",
    "title",
    "phone",
  ];
  const positiveFeeHints = [
    "tarif",
    "fee",
    "price",
    "livraison",
    "delivery",
    "home",
    "desk",
    "pickup",
    "stopdesk",
    "montant",
    "amount",
    "rate",
    "cost",
    "cout",
  ];
  for (const [key, raw] of Object.entries(record)) {
    const keyNorm = normalizeToken(key);
    if (!keyNorm) continue;
    if (ignored.some((token) => keyNorm.includes(token))) continue;
    if (!positiveFeeHints.some((token) => keyNorm.includes(token))) continue;
    const parsed = numberValue(raw);
    if (parsed != null && parsed > 0) return parsed;
  }
  return null;
};

type QuoteResult = {
  fee: number;
  baseFee: number;
  overweightFee: number;
  source: string;
  currency: "DZD";
};

const fallbackEstimate = (
  senderWilaya: string,
  receiverWilaya: string,
  weightKg: number,
  heightCm: number,
  widthCm: number,
  lengthCm: number,
): QuoteResult => {
  const sameWilaya = normalizeToken(senderWilaya) &&
      normalizeToken(senderWilaya) === normalizeToken(receiverWilaya);
  const baseFee = sameWilaya ? 300 : 700;
  const extraWeight = Math.max(0, weightKg - 5);
  const overweightFee = extraWeight * 70;
  const volumeCm3 = Math.max(0, heightCm) * Math.max(0, widthCm) * Math.max(0, lengthCm);
  const oversizeFee = volumeCm3 > 500000 ? 250 : volumeCm3 > 200000 ? 120 : 0;
  return {
    fee: Math.max(0, baseFee + overweightFee + oversizeFee),
    baseFee,
    overweightFee: overweightFee + oversizeFee,
    source: "fallback_rule",
    currency: "DZD",
  };
};

const parseEcotrackQuote = (
  decoded: unknown,
  toWilayaId: string,
  deliveryType: string,
  weightKg: number,
): QuoteResult | null => {
  if (!decoded || typeof decoded !== "object") return null;
  const root = decoded as Record<string, unknown>;
  const rows = extractList(root.livraison ?? root.data);
  if (rows.length === 0) return null;
  const target = rows.find((row) => {
    const rowId = textValue(row["wilaya_id"] ?? row["code"] ?? row["id"]);
    return !!rowId && normalizeToken(rowId) === normalizeToken(toWilayaId);
  }) ?? rows[0];
  const baseFee = deliveryType === "stopdesk"
    ? pickNumber(target, [
      "tarif_stopdesk",
      "stopdesk_tarif",
      "express_desk",
      "desk_fee",
      "tarif",
    ])
    : pickNumber(target, [
      "tarif",
      "home_tarif",
      "express_home",
      "home_fee",
      "tarif_stopdesk",
    ]);
  if (baseFee == null || baseFee < 0) return null;
  const threshold = pickNumber(target, [
    "overweight_threshold_kg",
    "overweight_threshold",
    "seuil_kg",
  ]) ?? 5;
  const extraPerKg = pickNumber(target, [
    "tarif_kg_supp",
    "supplement_kg",
    "extra_fee_per_kg",
    "overweight_fee_per_kg",
  ]) ??
      pickNumber(root, [
        "tarif_kg_supp",
        "supplement_kg",
        "extra_fee_per_kg",
        "overweight_fee_per_kg",
      ]);
  const overweightFee = extraPerKg == null
    ? 0
    : Math.ceil(Math.max(0, weightKg - threshold)) * extraPerKg;
  return {
    fee: Math.max(0, baseFee + overweightFee),
    baseFee,
    overweightFee,
    source: "carrier_api",
    currency: "DZD",
  };
};

const zrRateRows = (decoded: unknown): Array<Record<string, unknown>> => {
  if (Array.isArray(decoded)) {
    return decoded.filter((item): item is Record<string, unknown> =>
      !!item && typeof item === "object"
    );
  }
  if (!decoded || typeof decoded !== "object") return [];
  const root = decoded as Record<string, unknown>;
  const candidates = [root.rates, root.data, root.items, root.results];
  for (const candidate of candidates) {
    if (Array.isArray(candidate)) {
      return candidate.filter((item): item is Record<string, unknown> =>
        !!item && typeof item === "object"
      );
    }
  }
  if (root.data && typeof root.data === "object") {
    const nested = root.data as Record<string, unknown>;
    const nestedCandidates = [nested.rates, nested.items, nested.results];
    for (const candidate of nestedCandidates) {
      if (Array.isArray(candidate)) {
        return candidate.filter((item): item is Record<string, unknown> =>
          !!item && typeof item === "object"
        );
      }
    }
  }
  return [];
};

const parseZrQuote = (
  decoded: unknown,
  receiverWilayaId: string,
  receiverWilayaName: string,
  receiverCommuneId: string,
  receiverCommuneName: string,
  deliveryType: string,
): QuoteResult | null => {
  const rows = zrRateRows(decoded);
  if (rows.length === 0) return null;

  const deliveryKey = deliveryType === "stopdesk" ? "pickuppoint" : "home";
  const communeIdKey = normalizeToken(receiverCommuneId);
  const communeNameKey = normalizeToken(receiverCommuneName);
  const wilayaIdKey = normalizeToken(receiverWilayaId);
  const wilayaNameKey = normalizeToken(receiverWilayaName);

  const scored = rows
    .map((row) => {
      const rowIdKey = normalizeToken(row.toTerritoryId ?? row.id);
      const rowNameKey = normalizeToken(row.toTerritoryName ?? row.name);
      const rowLevelKey = normalizeToken(row.toTerritoryLevel ?? row.level);
      let score = 0;
      if (communeIdKey && rowIdKey === communeIdKey) score = 500;
      else if (communeNameKey && rowNameKey === communeNameKey) score = 450;
      else if (wilayaIdKey && rowIdKey === wilayaIdKey) score = 400;
      else if (wilayaNameKey && rowNameKey === wilayaNameKey) score = 350;
      if (score > 0) {
        if (rowLevelKey.includes("commune")) score += 20;
        if (rowLevelKey.includes("wilaya")) score += 10;
      }
      return { row, score };
    })
    .filter((item) => item.score > 0)
    .sort((a, b) => b.score - a.score);
  const target = scored[0]?.row;
  if (!target) return null;

  const deliveryPrices = Array.isArray(target.deliveryPrices)
    ? target.deliveryPrices.filter((item): item is Record<string, unknown> =>
      !!item && typeof item === "object"
    )
    : [];
  const priceRow =
    deliveryPrices.find((item) =>
      normalizeToken(item.deliveryType).includes(deliveryKey)
    ) ??
    deliveryPrices.find((item) =>
      deliveryKey === "pickuppoint"
        ? normalizeToken(item.deliveryType).includes("desk")
        : normalizeToken(item.deliveryType).includes("home")
    ) ??
    deliveryPrices[0];
  if (!priceRow) return null;

  const baseFee = pickNumber(priceRow, [
    "discountedPrice",
    "discounted_price",
    "price",
  ]);
  if (baseFee == null || baseFee < 0) return null;

  return {
    fee: Math.max(0, baseFee),
    baseFee,
    overweightFee: 0,
    source: "carrier_api",
    currency: "DZD",
  };
};

const guepexPerCommuneRows = (value: unknown): Array<Record<string, unknown>> => {
  if (!value || typeof value !== "object" || Array.isArray(value)) return [];
  const rows: Array<Record<string, unknown>> = [];
  for (const [communeId, raw] of Object.entries(value as Record<string, unknown>)) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) continue;
    rows.push({
      commune_id: communeId,
      ...(raw as Record<string, unknown>),
    });
  }
  return rows;
};

const guepexBillableWeightKg = (
  weightKg: number,
  heightCm: number,
  widthCm: number,
  lengthCm: number,
) => {
  const actualWeight = Math.max(1, Math.round(weightKg));
  const volumeCm3 = Math.max(0, heightCm) * Math.max(0, widthCm) * Math.max(0, lengthCm);
  if (volumeCm3 <= 0) return actualWeight;
  // Guepex fees are based on the larger of actual and volumetric weight.
  // Current live responses align with a 6000 cm3/kg divisor and integer truncation.
  const volumetricWeight = Math.max(1, Math.floor(volumeCm3 / 6000));
  return Math.max(actualWeight, volumetricWeight);
};

const parseGuepexQuote = (
  decoded: unknown,
  receiverCommuneId: string,
  receiverCommuneName: string,
  deliveryType: string,
  weightKg: number,
  heightCm: number,
  widthCm: number,
  lengthCm: number,
): QuoteResult | null => {
  if (!decoded || typeof decoded !== "object") return null;
  const root = decoded as Record<string, unknown>;
  const rows = guepexPerCommuneRows(root.per_commune);
  const normalizedCommuneId = normalizeToken(receiverCommuneId);
  const normalizedCommuneName = normalizeToken(receiverCommuneName);
  const target = rows.find((row) => {
    const rowId = normalizeToken(row.commune_id);
    if (normalizedCommuneId && rowId === normalizedCommuneId) return true;
    const rowName = normalizeToken(row.commune_name);
    return !!normalizedCommuneName && rowName === normalizedCommuneName;
  }) ?? rows[0];
  if (!target) return null;

  const baseFee = deliveryType === "stopdesk"
    ? pickNumber(target, ["express_desk", "desk_fee", "pickup_fee", "pickup_price"])
    : pickNumber(target, ["express_home", "home_fee", "delivery_fee", "delivery_price"]);
  if (baseFee == null || baseFee < 0) return null;

  const threshold = pickNumber(root, [
    "overweight_threshold_kg",
    "weight_threshold",
    "seuil_kg",
  ]) ?? 5;
  const surchargePerKg = pickNumber(root, [
    "oversize_fee",
    "overweight_fee",
    "overweight_fee_per_kg",
    "extra_fee_per_kg",
    "tarif_kg_supp",
    "supplement_kg",
  ]) ?? 0;
  const billableWeightKg = guepexBillableWeightKg(weightKg, heightCm, widthCm, lengthCm);
  const volumetricSurcharge = surchargePerKg > 0
    ? Math.max(0, billableWeightKg - threshold) * surchargePerKg
    : 0;
  const returnFee = pickNumber(root, ["retour_fee", "return_fee"]) ?? 0;
  const surchargeFee = Math.max(0, volumetricSurcharge + returnFee);

  return {
    fee: Math.max(0, baseFee + surchargeFee),
    baseFee,
    overweightFee: surchargeFee,
    source: "carrier_api",
    currency: "DZD",
  };
};

const parseGenericCarrierQuote = (
  decoded: unknown,
  deliveryType: string,
  weightKg: number,
): QuoteResult | null => {
  if (!decoded || typeof decoded !== "object") return null;
  const root = decoded as Record<string, unknown>;
  const rows = extractList(decoded);
  for (const row of rows.length === 0 ? [root] : rows) {
    const baseFee = deliveryType === "stopdesk"
      ? pickNumber(row, [
        "tarif_stopdesk",
        "stopdesk_fee",
        "express_desk",
        "desk_fee",
        "pickup_fee",
        "pickup_price",
        "rate_pickup",
      ]) ?? firstLikelyPrice(row)
      : pickNumber(row, [
        "tarif",
        "home_fee",
        "express_home",
        "home_price",
        "delivery_fee",
        "delivery_price",
        "rate_home",
      ]) ?? firstLikelyPrice(row);
    if (baseFee == null || baseFee < 0) continue;
    const threshold = pickNumber(row, [
      "overweight_threshold_kg",
      "weight_threshold",
      "seuil_kg",
    ]) ??
        pickNumber(root, [
          "overweight_threshold_kg",
          "weight_threshold",
          "seuil_kg",
        ]) ??
        5;
    const extraFee = pickNumber(row, [
      "overweight_fee",
      "overweight_fee_per_kg",
      "oversize_fee",
      "extra_fee_per_kg",
      "tarif_kg_supp",
      "supplement_kg",
    ]) ??
        pickNumber(root, [
          "overweight_fee",
          "overweight_fee_per_kg",
          "oversize_fee",
          "extra_fee_per_kg",
          "tarif_kg_supp",
          "supplement_kg",
        ]);
    const overweightFee = extraFee == null
      ? 0
      : Math.ceil(Math.max(0, weightKg - threshold)) * extraFee;
    return {
      fee: Math.max(0, baseFee + overweightFee),
      baseFee,
      overweightFee,
      source: "carrier_api",
      currency: "DZD",
    };
  }
  return null;
};

const canonicalCarrierCode = (courierId: string, courierName: string) => {
  const normalized = normalizeCourier(`${courierId} ${courierName}`);
  if (normalized.includes("yalidine")) return "yalidine";
  if (normalized.includes("ecotrack")) return "ecotrack";
  if (normalized.includes("zrexpress")) return "zrexpress";
  if (normalized.includes("guepex")) return "guepex";
  return normalizeCourier(courierId);
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
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

  const token = auth.replace(/^Bearer\s+/i, "").trim();
  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false },
  });

  let userId = "";
  try {
    const { data, error } = await admin.auth.getUser(token);
    if (error) throw error;
    userId = data.user?.id ?? "";
  } catch {
    userId = "";
  }
  if (!userId) return jsonResponse({ ok: false, message: "Unauthorized" }, 401);

  try {
    const ok = await consumeRateLimit(admin, `shipping_quote:${userId}`, 40, 60);
    if (!ok) {
      return jsonResponse({ ok: false, message: "Rate limit exceeded" }, 429);
    }
  } catch {
    return jsonResponse({ ok: false, message: "Rate limit error" }, 500);
  }

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ ok: false, message: "Invalid JSON" }, 400);
  }

  const sellerId = textValue(payload.seller_id);
  const courierId = textValue(payload.courier_id);
  const courierName = textValue(payload.courier_name);
  const productId = textValue(payload.product_id);
  const deliveryType = textValue(payload.delivery_type) || "home";
  const senderWilayaId = textValue(payload.sender_wilaya_id);
  const senderWilayaName = textValue(payload.sender_wilaya_name);
  const receiverWilayaId = textValue(payload.receiver_wilaya_id);
  const receiverWilayaName = textValue(payload.receiver_wilaya_name);
  const receiverCommuneId = textValue(payload.receiver_commune_id);
  const receiverCommuneName = textValue(payload.receiver_commune_name);
  const weightKg = Math.max(1, Math.round(numberValue(payload.weight_kg) ?? 1));
  const heightCm = Math.max(0, Math.round(numberValue(payload.height_cm) ?? 0));
  const widthCm = Math.max(0, Math.round(numberValue(payload.width_cm) ?? 0));
  const lengthCm = Math.max(0, Math.round(numberValue(payload.length_cm) ?? 0));
  const price = Math.max(0, numberValue(payload.price) ?? 0);
  const declaredValue = Math.max(0, numberValue(payload.declared_value) ?? price);

  if (!sellerId || !courierId) {
    return jsonResponse({ ok: false, message: "seller_id and courier_id required" }, 400);
  }

  let shippingFree = false;
  let effectiveSenderWilayaId = senderWilayaId;
  let effectiveSenderWilayaName = senderWilayaName;
  if (productId) {
    const { data: product } = await admin
      .from("products")
      .select("id,owner_id,shipping_free,location_wilaya")
      .eq("id", productId)
      .maybeSingle();
    if (product) {
      if (textValue(product.owner_id) && textValue(product.owner_id) !== sellerId) {
        return jsonResponse({ ok: false, message: "seller mismatch for product" }, 403);
      }
      shippingFree = product.shipping_free === true;
      if (!effectiveSenderWilayaName) {
        effectiveSenderWilayaName = textValue(product.location_wilaya);
      }
    }
  }

  if (shippingFree) {
    return jsonResponse({
      ok: true,
      fee: 0,
      base_fee: 0,
      overweight_fee: 0,
      currency: "DZD",
      source: "free_shipping",
      free_shipping: true,
      courier_code: canonicalCarrierCode(courierId, courierName),
    });
  }

  const carrierCode = canonicalCarrierCode(courierId, courierName);
  const senderRouteValue = effectiveSenderWilayaId || effectiveSenderWilayaName;
  const receiverRouteValue = receiverWilayaId || receiverWilayaName;
  let apiKey = "";
  let apiSecret = "";

  try {
    const { data: secureRows } = await admin.rpc("get_seller_delivery_settings_secure", {
      p_owner: sellerId,
      p_courier_id: courierId,
    });
    if (Array.isArray(secureRows) && secureRows.length > 0) {
      const secureRow = (secureRows[0] ?? {}) as Record<string, unknown>;
      apiKey = textValue(secureRow.api_key);
      apiSecret = textValue(secureRow.api_secret);
    }
  } catch {
    // Fallback to plain fields when secure function is unavailable.
  }

  if (!apiKey) {
    const { data: settings } = await admin
      .from("seller_delivery_settings")
      .select("api_key,api_secret")
      .eq("owner_id", sellerId)
      .eq("courier_id", courierId)
      .maybeSingle();
    apiKey = textValue(settings?.api_key);
    apiSecret = textValue(settings?.api_secret);
  }

  if (!apiKey) {
    const fallback = fallbackEstimate(
      senderRouteValue,
      receiverRouteValue,
      weightKg,
      heightCm,
      widthCm,
      lengthCm,
    );
    return jsonResponse({
      ok: true,
      fee: fallback.fee,
      base_fee: fallback.baseFee,
      overweight_fee: fallback.overweightFee,
      currency: fallback.currency,
      source: fallback.source,
      free_shipping: false,
      courier_code: carrierCode,
      meta: { warning: "missing_seller_courier_settings" },
    });
  }

  let quote: QuoteResult | null = null;
  try {
    if (carrierCode === "ecotrack") {
      for (const base of ecotrackBaseUrls()) {
        const resp = await carrierFetch(
          admin,
          carrierCode,
          sellerId,
          `${base}/api/v1/get/fees`,
          {
            method: "GET",
            headers: {
              Authorization: `Bearer ${apiKey}`,
              Accept: "application/json",
            },
          },
        );
        if (!resp) return jsonResponse({ ok: false, message: "courier_rate_limited" }, 429);
        if (!resp.ok) {
          if (resp.status === 404 || resp.status === 405) continue;
          break;
        }
        quote = parseEcotrackQuote(await resp.json(), receiverRouteValue, deliveryType, weightKg);
        if (quote) break;
      }
    } else if (carrierCode === "guepex") {
      const base = (Deno.env.get("GUEPEX_BASE_URL") ?? "https://api.guepex.app").replace(
        /\/+$/,
        "",
      );
      const route = new URL(`${base}/v1/fees/`);
      if (senderRouteValue) route.searchParams.set("from_wilaya_id", senderRouteValue);
      if (receiverRouteValue) route.searchParams.set("to_wilaya_id", receiverRouteValue);
      const resp = await carrierFetch(
        admin,
        carrierCode,
        sellerId,
        route.toString(),
        {
          method: "GET",
          headers: {
            "X-API-ID": apiKey,
            "X-API-TOKEN": apiSecret,
            Accept: "application/json",
          },
        },
      );
      if (!resp) return jsonResponse({ ok: false, message: "courier_rate_limited" }, 429);
      if (resp.ok) {
        quote = parseGuepexQuote(
          await resp.json(),
          receiverCommuneId,
          receiverCommuneName,
          deliveryType,
          weightKg,
          heightCm,
          widthCm,
          lengthCm,
        );
      }
    } else if (carrierCode === "yalidine") {
      const route = new URL("https://api.yalidine.app/v1/fees/");
      if (senderRouteValue) route.searchParams.set("from_wilaya_id", senderRouteValue);
      if (receiverRouteValue) route.searchParams.set("to_wilaya_id", receiverRouteValue);
      const resp = await carrierFetch(
        admin,
        carrierCode,
        sellerId,
        route.toString(),
        {
          method: "GET",
          headers: {
            "X-API-ID": apiKey,
            "X-API-TOKEN": apiSecret,
            Accept: "application/json",
          },
        },
      );
      if (!resp) return jsonResponse({ ok: false, message: "courier_rate_limited" }, 429);
      if (resp.ok) {
        quote = parseGuepexQuote(
          await resp.json(),
          receiverCommuneId,
          receiverCommuneName,
          deliveryType,
          weightKg,
          heightCm,
          widthCm,
          lengthCm,
        );
      }
    } else if (carrierCode === "zrexpress") {
      const resp = await carrierFetch(
        admin,
        carrierCode,
        sellerId,
        "https://api.zrexpress.app/api/v1/delivery-pricing/rates",
        {
          method: "GET",
          headers: {
            "X-Api-Key": apiKey,
            "X-Tenant": apiSecret,
            Accept: "application/json",
          },
        },
      );
      if (!resp) return jsonResponse({ ok: false, message: "courier_rate_limited" }, 429);
      if (resp.ok) {
        quote = parseZrQuote(
          await resp.json(),
          receiverWilayaId,
          receiverWilayaName,
          receiverCommuneId,
          receiverCommuneName,
          deliveryType,
        );
      }
    }
  } catch {
    quote = null;
  }

  if (!quote) {
    quote = fallbackEstimate(
      senderRouteValue,
      receiverRouteValue,
      weightKg,
      heightCm,
      widthCm,
      lengthCm,
    );
  }

  // Guardrail for malformed carrier payloads (observed tiny values like 2-3 DZD).
  if (
    (carrierCode === "guepex" || carrierCode === "yalidine" || carrierCode === "zrexpress") &&
    quote &&
    quote.fee > 0 &&
    quote.fee < 50
  ) {
    quote = fallbackEstimate(
      senderRouteValue,
      receiverRouteValue,
      weightKg,
      heightCm,
      widthCm,
      lengthCm,
    );
  }

  return jsonResponse({
    ok: true,
    fee: quote.fee,
    base_fee: quote.baseFee,
    overweight_fee: quote.overweightFee,
    currency: quote.currency,
    source: quote.source,
    free_shipping: false,
    courier_code: carrierCode,
    meta: {
      seller_id: sellerId,
      courier_id: courierId,
      courier_name: courierName,
      delivery_type: deliveryType,
      sender_wilaya: senderRouteValue,
      receiver_wilaya: receiverRouteValue,
      receiver_commune: receiverCommuneId || receiverCommuneName,
      declared_value: declaredValue,
      price,
      weight_kg: weightKg,
      height_cm: heightCm,
      width_cm: widthCm,
      length_cm: lengthCm,
    },
  });
});
