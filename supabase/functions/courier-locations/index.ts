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

const mapDbCommunes = (rows: Array<Record<string, unknown>>) =>
  rows
    .map((r) => ({
      id: "",
      name: textValue(r.name_fr) || textValue(r.name_ar),
      wilaya_id: "",
      has_stop_desk: "0",
      stopdesk_id: "",
    }))
    .filter((m) => m.name);

const boolValue = (value: unknown) => {
  if (typeof value === "boolean") return value;
  const normalized = textValue(value).toLowerCase();
  return normalized === "true" || normalized === "1";
};

const extractList = (decoded: unknown) => {
  if (Array.isArray(decoded)) return decoded;
  if (decoded && typeof decoded === "object") {
    const obj = decoded as Record<string, unknown>;
    if (Array.isArray(obj.data)) return obj.data;
    if (Array.isArray(obj.items)) return obj.items;
    if (Array.isArray(obj.results)) return obj.results;
    const nested = obj.data as Record<string, unknown> | undefined;
    if (nested && Array.isArray(nested.items)) return nested.items;
  }
  return [];
};

const normalizeName = (value: unknown) =>
  textValue(value)
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "");

const cacheTtlMs = 1000 * 60 * 60 * 24 * 15;

const guepexBaseUrl = () =>
  (Deno.env.get("GUEPEX_BASE_URL") ?? "https://api.guepex.app")
    .trim()
    .replace(/\/+$/, "");

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

const codeVariants = (value: string) =>
  Array.from(
    new Set(
      [
        value,
        value.replace(/^0+/, ""),
        value.padStart(2, "0"),
      ].filter((v) => v),
    ),
  );

const inCodeVariants = (value: unknown, expected: string) => {
  const normalized = textValue(value);
  if (!normalized || !expected) return false;
  const variants = codeVariants(expected);
  return variants.includes(normalized);
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

const locationCarrierRatePolicy = (carrierCode: string): CarrierRateWindow[] => {
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
      return [{ limit: 5, seconds: 1 }, { limit: 60, seconds: 60 }];
  }
};

const enforceCarrierRateLimit = async (
  supabase: ReturnType<typeof createClient>,
  carrierCode: string,
  ownerId: string,
) => {
  if (!carrierCode || !ownerId) return true;
  for (const window of locationCarrierRatePolicy(carrierCode)) {
    const ok = await consumeRateLimit(
      supabase,
      `carrier_loc:${carrierCode}:${ownerId}:${window.seconds}`,
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

const zrSearch = async (
  supabase: ReturnType<typeof createClient>,
  carrierCode: string,
  ownerId: string,
  path: string,
  bodies: Array<Record<string, unknown>>,
  headers: Record<string, string>,
) => {
  const baseUrl = "https://api.zrexpress.app";
  for (const body of bodies) {
    const resp = await carrierFetch(
      supabase,
      carrierCode,
      ownerId,
      `${baseUrl}${path}`,
      {
        method: "POST",
        headers,
        body: JSON.stringify(body),
      },
    );
    if (!resp) return [];
    if (!resp.ok) continue;
    const decoded = await resp.json();
    const list = extractList(decoded);
    if (list.length) return list;
  }
  return [];
};

const mapCacheWilayas = (rows: Array<Record<string, unknown>>) =>
  rows
    .map((r) => ({
      id: textValue(r.remote_id),
      code: textValue(r.wilaya_code) || textValue(r.remote_id),
      name: textValue(r.name_raw),
    }))
    .filter((m) => m.name);

const mapCacheCommunes = (rows: Array<Record<string, unknown>>) =>
  rows
    .map((r) => {
      const extra = (r.extra as Record<string, unknown>) ?? {};
      return {
        id: textValue(r.remote_id),
        name: textValue(r.name_raw),
        wilaya_id: textValue(r.parent_remote_id) || textValue(r.wilaya_code),
        has_stop_desk: textValue(extra.has_stop_desk ?? extra.hasStopDesk ?? "0"),
        stopdesk_id: textValue(extra.stopdesk_id ?? extra.stopdeskId ?? ""),
      };
    })
    .filter((m) => m.name);

const readCache = async (
  supabase: ReturnType<typeof createClient>,
  courierKey: string,
  type: string,
  parentId?: string,
) => {
  let query = supabase
    .from("courier_locations")
    .select("remote_id,name_raw,parent_remote_id,wilaya_code,extra,updated_at")
    .eq("courier_key", courierKey)
    .eq("type", type);
  if (parentId) query = query.eq("parent_remote_id", parentId);
  const { data } = await query;
  if (!data || data.length === 0) return null;
  let latest = 0;
  for (const row of data) {
    const ts = Date.parse(textValue(row.updated_at));
    if (!Number.isNaN(ts) && ts > latest) latest = ts;
  }
  if (latest && Date.now() - latest > cacheTtlMs) return null;
  return data as Array<Record<string, unknown>>;
};

const writeCache = async (
  supabase: ReturnType<typeof createClient>,
  courierKey: string,
  courierId: string,
  type: string,
  rows: Array<Record<string, unknown>>,
) => {
  if (!rows.length) return;
  const payload = rows.map((r) => ({
    courier_key: courierKey,
    courier_id: courierId,
    type,
    remote_id: textValue(r.remote_id) || textValue(r.id) || textValue(r.code) || textValue(r.name_raw),
    name_raw: textValue(r.name_raw) || textValue(r.name),
    name_norm: normalizeName(r.name_raw ?? r.name),
    parent_remote_id: textValue(r.parent_remote_id),
    wilaya_code: textValue(r.wilaya_code),
    extra: r.extra ?? {},
    updated_at: new Date().toISOString(),
  }));
  await supabase.from("courier_locations").upsert(payload, {
    onConflict: "courier_key,type,remote_id,parent_remote_id",
  });
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ ok: false, message: "Method not allowed" }, 405);

  const auth = req.headers.get("authorization") ?? "";
  if (!auth.startsWith("Bearer ")) {
    return jsonResponse({ ok: false, message: "Unauthorized" }, 401);
  }

  let payload: {
    seller_id?: string;
    courier_id?: string;
    wilaya_code?: string;
    type?: string;
  };
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ ok: false, message: "Invalid JSON" }, 400);
  }

  const sellerId = textValue(payload.seller_id);
  const courierId = textValue(payload.courier_id);
  const wilayaCode = textValue(payload.wilaya_code);
  const requestType = textValue(payload.type) || "communes";
  if (!sellerId || !courierId) {
    return jsonResponse({ ok: false, message: "Missing parameters" }, 400);
  }
  if (requestType === "communes" && !wilayaCode) {
    return jsonResponse({ ok: false, message: "Missing wilaya_code" }, 400);
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
  if (userError || !userData?.user) {
    return jsonResponse({ ok: false, message: "Unauthorized" }, 401);
  }

  try {
    const ok = await consumeRateLimit(
      supabaseUser,
      `courier_locations:${userData.user.id}`,
      30,
      60,
    );
    if (!ok) {
      return jsonResponse({ ok: false, message: "Rate limit exceeded" }, 429);
    }
  } catch {
    return jsonResponse({ ok: false, message: "Rate limit error" }, 500);
  }

  const variants = Array.from(
    new Set([courierId, courierId.toLowerCase(), courierId.toUpperCase()]),
  );
  const normalizeCourier = (value: string) =>
    value.toLowerCase().replace(/[^a-z0-9]/g, "");
  const normalizedVariants = variants.map(normalizeCourier);
  const courierKey = normalizeCourier(courierId);

  const { data: settingsRow } = await supabaseAdmin
    .from("seller_delivery_settings")
    .select("api_key, api_secret")
    .eq("owner_id", sellerId)
    .in("courier_id", variants)
    .maybeSingle();

  if (!settingsRow?.api_key) {
    return jsonResponse({ ok: true, data: [] });
  }

  const isYalidine = normalizedVariants.some((v) => v.includes("yalidine"));
  const isEcotrack = normalizedVariants.some((v) => v.includes("ecotrack"));
  const isZrExpress = normalizedVariants.some((v) => v.includes("zrexpress"));
  const isGuepex = normalizedVariants.some((v) => v.includes("guepex"));
  const carrierCode = isYalidine
    ? "yalidine"
    : isEcotrack
    ? "ecotrack"
    : isZrExpress
    ? "zrexpress"
    : isGuepex
    ? "guepex"
    : "generic";
  const carrierOwnerId = sellerId || userData.user.id;

  const cacheType = requestType === "wilayas" ? "wilaya" : "commune";
  if (courierKey) {
    const cached = await readCache(
      supabaseAdmin,
      courierKey,
      cacheType,
      requestType === "communes" ? wilayaCode : undefined,
    );
    if (cached) {
      const data =
        requestType === "wilayas"
          ? mapCacheWilayas(cached)
          : mapCacheCommunes(cached);
      if (data.length) return jsonResponse({ ok: true, data });
    }
  }

  if (requestType === "wilayas") {
    if (isYalidine && settingsRow.api_secret) {
      const url = "https://api.yalidine.app/v1/wilayas/";
      const resp = await carrierFetch(
        supabaseUser,
        carrierCode,
        carrierOwnerId,
        url,
        {
          method: "GET",
          headers: {
            "X-API-ID": textValue(settingsRow.api_key),
            "X-API-TOKEN": textValue(settingsRow.api_secret),
            Accept: "application/json",
          },
        },
      );
      if (!resp) return jsonResponse({ ok: false, message: "courier_rate_limited" }, 429);
      if (resp.ok) {
        const decoded = await resp.json();
        const data = decoded?.data ?? decoded;
        if (Array.isArray(data)) {
          const list = data
            .map((m) => ({
              id: textValue(m.id),
              code: textValue(m.wilaya_code),
              name: textValue(m.wilaya_name) || textValue(m.name),
            }))
            .filter((m) => m.name);
          await writeCache(
            supabaseAdmin,
            courierKey,
            courierId,
            "wilaya",
            list.map((m) => ({
              remote_id: m.id || m.code,
              name_raw: m.name,
              wilaya_code: m.code,
            })),
          );
          return jsonResponse({ ok: true, data: list });
        }
      }
    }

    if (isEcotrack) {
      for (const base of ecotrackBaseUrls()) {
        const resp = await carrierFetch(
          supabaseUser,
          carrierCode,
          carrierOwnerId,
          `${base}/api/v1/get/fees`,
          {
            method: "GET",
            headers: {
              Authorization: `Bearer ${textValue(settingsRow.api_key)}`,
              Accept: "application/json",
            },
          },
        );
        if (!resp) return jsonResponse({ ok: false, message: "courier_rate_limited" }, 429);
        if (!resp.ok) {
          if (resp.status === 404 || resp.status === 405) continue;
          break;
        }
        const decoded = await resp.json();
        const livraison = decoded?.livraison;
        if (Array.isArray(livraison)) {
          const ids = Array.from(
            new Set(
              livraison
                .map((m: Record<string, unknown>) => textValue(m.wilaya_id))
                .filter((id) => id),
            ),
          );
          if (ids.length) {
            const expanded = Array.from(new Set(ids.flatMap((id) => {
              const trimmed = id.replace(/^0+/, "");
              const padded = trimmed.padStart(2, "0");
              return [id, trimmed, padded];
            }))).filter((v) => v);
            const { data: rows } = await supabaseAdmin
              .from("wilayas")
              .select("code, name_fr, name_ar")
              .in("code", expanded);
            if (rows && rows.length) {
              const list = rows
                .map((r) => ({
                  id: textValue(r.code),
                  code: textValue(r.code),
                  name: textValue(r.name_fr) || textValue(r.name_ar),
                }))
                .filter((m) => m.name);
              await writeCache(
                supabaseAdmin,
                courierKey,
                courierId,
                "wilaya",
                list.map((m) => ({
                  remote_id: m.id || m.code,
                  name_raw: m.name,
                  wilaya_code: m.code,
                })),
              );
              return jsonResponse({ ok: true, data: list });
            }
          }
        }
      }
    }

    if (isGuepex && settingsRow.api_secret) {
      const url = `${guepexBaseUrl()}/v1/wilayas`;
      const resp = await carrierFetch(
        supabaseUser,
        carrierCode,
        carrierOwnerId,
        url,
        {
          method: "GET",
          headers: {
            "X-API-ID": textValue(settingsRow.api_key),
            "X-API-TOKEN": textValue(settingsRow.api_secret),
            Accept: "application/json",
          },
        },
      );
      if (!resp) return jsonResponse({ ok: false, message: "courier_rate_limited" }, 429);
      if (resp.ok) {
        const decoded = await resp.json();
        const data = extractList(decoded);
        if (Array.isArray(data)) {
          const list = data
            .map((m) => ({
              id: textValue((m as Record<string, unknown>)?.id) ||
                textValue((m as Record<string, unknown>)?.wilaya_id) ||
                textValue((m as Record<string, unknown>)?.code) ||
                textValue((m as Record<string, unknown>)?.wilaya_code),
              code: textValue((m as Record<string, unknown>)?.wilaya_code) ||
                textValue((m as Record<string, unknown>)?.code) ||
                textValue((m as Record<string, unknown>)?.id) ||
                textValue((m as Record<string, unknown>)?.wilaya_id),
              name: textValue((m as Record<string, unknown>)?.wilaya_name) ||
                textValue((m as Record<string, unknown>)?.name) ||
                textValue((m as Record<string, unknown>)?.name_fr),
            }))
            .filter((m) => m.name);
          if (list.length) {
            await writeCache(
              supabaseAdmin,
              courierKey,
              courierId,
              "wilaya",
              list.map((m) => ({
                remote_id: m.id || m.code,
                name_raw: m.name,
                wilaya_code: m.code,
              })),
            );
            return jsonResponse({ ok: true, data: list });
          }
        }
      }
    }

    if (isZrExpress && settingsRow.api_secret) {
      const headers = {
        "X-Api-Key": textValue(settingsRow.api_key),
        "X-Tenant": textValue(settingsRow.api_secret),
        "Content-Type": "application/json",
        Accept: "application/json",
      };
      const bodies = [
        {
          page: 1,
          pageSize: 5000,
          orderBy: ["code asc"],
          advancedFilter: {
            rules: [{ field: "level", operator: "eq", value: "City" }],
          },
        },
        { page: 1, pageSize: 5000, orderBy: ["code asc"] },
        { pageNumber: 1, pageSize: 5000, orderBy: ["code asc"] },
      ];
      const list = await zrSearch(
        supabaseUser,
        carrierCode,
        carrierOwnerId,
        "/api/v1/territories/search",
        bodies,
        headers,
      );
      if (list.length) {
        const mapped = list
          .map((m) => {
            const parentId = textValue((m as Record<string, unknown>)?.parentId);
            const level = textValue((m as Record<string, unknown>)?.level).toLowerCase();
            const isWilaya = (!parentId) || level.includes("wilaya") || level.includes("city");
            return isWilaya
              ? {
                  id: textValue((m as Record<string, unknown>)?.id),
                  code: textValue((m as Record<string, unknown>)?.code),
                  name: textValue((m as Record<string, unknown>)?.name),
                }
              : null;
          })
          .filter((m): m is Record<string, string> => !!m && !!m.name);
        if (mapped.length) {
          await writeCache(
            supabaseAdmin,
            courierKey,
            courierId,
            "wilaya",
            mapped.map((m) => ({
              remote_id: m.id || m.code,
              name_raw: m.name,
              wilaya_code: m.code,
            })),
          );
          return jsonResponse({ ok: true, data: mapped });
        }
      }
    }

    if (isZrExpress) {
      return jsonResponse({ ok: true, data: [] });
    }

    const { data: rows } = await supabaseAdmin
      .from("wilayas")
      .select("code, name_fr, name_ar")
      .order("code");
    const fallback = (rows ?? [])
      .map((r) => ({
        id: textValue(r.code),
        code: textValue(r.code),
        name: textValue(r.name_fr) || textValue(r.name_ar),
      }))
      .filter((m) => m.name);
    await writeCache(
      supabaseAdmin,
      courierKey,
      courierId,
      "wilaya",
      fallback.map((m) => ({
        remote_id: m.id || m.code,
        name_raw: m.name,
        wilaya_code: m.code,
      })),
    );
    return jsonResponse({ ok: true, data: fallback });
  }

  if (isYalidine && settingsRow.api_secret) {
    const url = `https://api.yalidine.app/v1/communes?wilaya_id=${encodeURIComponent(wilayaCode)}`;
    const resp = await carrierFetch(
      supabaseUser,
      carrierCode,
      carrierOwnerId,
      url,
      {
        method: "GET",
        headers: {
          "X-API-ID": textValue(settingsRow.api_key),
          "X-API-TOKEN": textValue(settingsRow.api_secret),
          Accept: "application/json",
        },
      },
    );
    if (!resp) return jsonResponse({ ok: false, message: "courier_rate_limited" }, 429);
    if (!resp.ok) {
      return jsonResponse({ ok: false, message: "Yalidine communes failed" }, 502);
    }
    const decoded = await resp.json();
    const data = decoded?.data ?? decoded;
    if (Array.isArray(data)) {
      const list = data
        .map((m) => ({
          id: textValue(m.id),
          name: textValue(m.commune_name) || textValue(m.name),
          wilaya_id: textValue(m.wilaya_id),
          has_stop_desk: textValue(m.has_stop_desk),
          stopdesk_id: textValue(m.stopdesk_id),
        }))
        .filter((m) => m.name);
      await writeCache(
        supabaseAdmin,
        courierKey,
        courierId,
        "commune",
        list.map((m) => ({
          remote_id: m.id || m.name,
          name_raw: m.name,
          parent_remote_id: m.wilaya_id || wilayaCode,
          wilaya_code: wilayaCode,
          extra: {
            has_stop_desk: m.has_stop_desk,
            stopdesk_id: m.stopdesk_id,
          },
        })),
      );
      return jsonResponse({ ok: true, data: list });
    }
  }

  if (isEcotrack) {
    const attempts = Array.from(
      new Set([
        wilayaCode,
        wilayaCode.replace(/^0+/, ""),
        wilayaCode.padStart(2, "0"),
      ].filter((v) => v)),
    );
    for (const base of ecotrackBaseUrls()) {
      for (const code of attempts) {
        const resp = await carrierFetch(
          supabaseUser,
          carrierCode,
          carrierOwnerId,
          `${base}/api/v1/get/communes?wilaya_id=${encodeURIComponent(code)}`,
          {
            method: "GET",
            headers: {
              Authorization: `Bearer ${textValue(settingsRow.api_key)}`,
              Accept: "application/json",
            },
          },
        );
        if (!resp) return jsonResponse({ ok: false, message: "courier_rate_limited" }, 429);
        if (!resp.ok) {
          if (resp.status === 404 || resp.status === 405) continue;
          break;
        }
        const decoded = await resp.json();
        const data = Array.isArray(decoded) ? decoded : decoded?.data;
        if (Array.isArray(data)) {
          const list = data
            .map((m) => ({
              id: textValue(m.id) || textValue(m.code) || textValue(m.commune),
              name: textValue(m.commune) || textValue(m.name),
              wilaya_id: wilayaCode,
              has_stop_desk: "0",
              stopdesk_id: "",
            }))
            .filter((m) => m.name);
          if (list.length) {
            await writeCache(
              supabaseAdmin,
              courierKey,
              courierId,
              "commune",
              list.map((m) => ({
                remote_id: m.id || m.name,
                name_raw: m.name,
                parent_remote_id: wilayaCode,
                wilaya_code: wilayaCode,
              })),
            );
            return jsonResponse({ ok: true, data: list });
          }
        }
      }
    }
  }

  if (isGuepex && settingsRow.api_secret) {
    const headers = {
      "X-API-ID": textValue(settingsRow.api_key),
      "X-API-TOKEN": textValue(settingsRow.api_secret),
      Accept: "application/json",
    };
    const baseUrl = guepexBaseUrl();
    const attempts = codeVariants(wilayaCode);

    let communesRaw: unknown[] = [];
    const communeUrls = [
      ...attempts.map((code) => `${baseUrl}/v1/communes?wilaya_id=${encodeURIComponent(code)}`),
      ...attempts.map((code) => `${baseUrl}/v1/communes?to_wilaya_id=${encodeURIComponent(code)}`),
      `${baseUrl}/v1/communes`,
    ];
    for (const url of communeUrls) {
      const resp = await carrierFetch(
        supabaseUser,
        carrierCode,
        carrierOwnerId,
        url,
        { method: "GET", headers },
      );
      if (!resp) return jsonResponse({ ok: false, message: "courier_rate_limited" }, 429);
      if (!resp.ok) continue;
      const decoded = await resp.json();
      const list = extractList(decoded);
      if (!list.length) continue;
      communesRaw = list;
      if (!url.endsWith("/communes")) break;
    }

    if (communesRaw.length) {
      let mapped = communesRaw
        .map((m) => ({
          id: textValue((m as Record<string, unknown>)?.id) ||
            textValue((m as Record<string, unknown>)?.commune_id) ||
            textValue((m as Record<string, unknown>)?.code),
          name: textValue((m as Record<string, unknown>)?.commune_name) ||
            textValue((m as Record<string, unknown>)?.name),
          wilaya_id: textValue((m as Record<string, unknown>)?.wilaya_id) ||
            textValue((m as Record<string, unknown>)?.to_wilaya_id) ||
            textValue((m as Record<string, unknown>)?.wilaya_code),
          has_stop_desk: "0",
          stopdesk_id: "",
        }))
        .filter((m) => m.name);

      const filteredByWilaya = mapped.filter((m) =>
        m.wilaya_id ? inCodeVariants(m.wilaya_id, wilayaCode) : true
      );
      if (filteredByWilaya.length > 0) mapped = filteredByWilaya;

      const uniqueMap = new Map<string, (typeof mapped)[number]>();
      for (const commune of mapped) {
        const id = commune.id || normalizeName(commune.name);
        const key = `${id}:${normalizeName(commune.name)}`;
        if (!uniqueMap.has(key)) uniqueMap.set(key, commune);
      }
      const uniqueCommunes = Array.from(uniqueMap.values());

      let centersRaw: unknown[] = [];
      const centerUrls = [
        ...attempts.map((code) => `${baseUrl}/v1/centers?wilaya_id=${encodeURIComponent(code)}`),
        ...attempts.map((code) => `${baseUrl}/v1/centers?to_wilaya_id=${encodeURIComponent(code)}`),
        `${baseUrl}/v1/centers`,
      ];
      for (const url of centerUrls) {
        const resp = await carrierFetch(
          supabaseUser,
          carrierCode,
          carrierOwnerId,
          url,
          { method: "GET", headers },
        );
        if (!resp) return jsonResponse({ ok: false, message: "courier_rate_limited" }, 429);
        if (!resp.ok) continue;
        const decoded = await resp.json();
        const list = extractList(decoded);
        if (!list.length) continue;
        centersRaw = list;
        if (!url.endsWith("/centers")) break;
      }

      const stopdeskByCommuneId = new Map<string, string>();
      const stopdeskByCommuneName = new Map<string, string>();
      if (centersRaw.length) {
        for (const center of centersRaw) {
          const row = center as Record<string, unknown>;
          const centerWilayaId = textValue(row.wilaya_id ?? row.to_wilaya_id ?? row.wilaya_code);
          if (centerWilayaId && !inCodeVariants(centerWilayaId, wilayaCode)) continue;
          const centerId = textValue(row.id ?? row.center_id ?? row.code);
          if (!centerId) continue;
          const communeId = textValue(
            row.commune_id ?? row.to_commune_id ?? row.district_id ?? row.city_id,
          );
          const communeName = normalizeName(
            row.commune_name ?? row.to_commune_name ?? row.commune ?? row.name,
          );
          if (communeId && !stopdeskByCommuneId.has(communeId)) {
            stopdeskByCommuneId.set(communeId, centerId);
          }
          if (communeName && !stopdeskByCommuneName.has(communeName)) {
            stopdeskByCommuneName.set(communeName, centerId);
          }
        }
      }

      const enriched = uniqueCommunes.map((commune) => {
        const stopdeskId = stopdeskByCommuneId.get(commune.id) ??
          stopdeskByCommuneName.get(normalizeName(commune.name)) ??
          "";
        return {
          ...commune,
          has_stop_desk: stopdeskId ? "1" : "0",
          stopdesk_id: stopdeskId,
          wilaya_id: commune.wilaya_id || wilayaCode,
        };
      });

      if (enriched.length) {
        await writeCache(
          supabaseAdmin,
          courierKey,
          courierId,
          "commune",
          enriched.map((commune) => ({
            remote_id: commune.id || normalizeName(commune.name),
            name_raw: commune.name,
            parent_remote_id: commune.wilaya_id || wilayaCode,
            wilaya_code: wilayaCode,
            extra: {
              has_stop_desk: commune.has_stop_desk,
              stopdesk_id: commune.stopdesk_id,
            },
          })),
        );
        return jsonResponse({ ok: true, data: enriched });
      }
    }
  }

  if (isZrExpress && settingsRow.api_secret) {
    const headers = {
      "X-Api-Key": textValue(settingsRow.api_key),
      "X-Tenant": textValue(settingsRow.api_secret),
      "Content-Type": "application/json",
      Accept: "application/json",
    };
    const bodies = [
      {
        page: 1,
        pageSize: 5000,
        advancedFilter: {
          rules: [{ field: "parentId", operator: "eq", value: wilayaCode }],
        },
      },
      {
        pageNumber: 1,
        pageSize: 5000,
        advancedFilter: {
          rules: [{ field: "parentId", operator: "eq", value: wilayaCode }],
        },
      },
      { page: 1, pageSize: 5000 },
    ];
    const list = await zrSearch(
      supabaseUser,
      carrierCode,
      carrierOwnerId,
      "/api/v1/territories/search",
      bodies,
      headers,
    );
    const communes = list
      .map((m) => {
        const parentId = textValue((m as Record<string, unknown>)?.parentId);
        if (parentId && parentId !== wilayaCode) return null;
        const level = textValue((m as Record<string, unknown>)?.level).toLowerCase();
        if (level && !(level.includes("commune") || level.includes("district"))) {
          return null;
        }
        return {
          id: textValue((m as Record<string, unknown>)?.id),
          name: textValue((m as Record<string, unknown>)?.name),
          wilaya_id: wilayaCode,
          has_stop_desk: "0",
          stopdesk_id: "",
        };
      })
      .filter((m): m is Record<string, string> => !!m && !!m.name);

    if (communes.length) {
      const hubBodies = [
        {
          page: 1,
          pageSize: 5000,
          advancedFilter: {
            rules: [{ field: "IsPickupPoint", operator: "eq", value: true }],
          },
        },
        { page: 1, pageSize: 5000 },
      ];
      const hubs = await zrSearch(
        supabaseUser,
        carrierCode,
        carrierOwnerId,
        "/api/v1/hubs/search",
        hubBodies,
        headers,
      );
      const hubsByCommune = new Map<string, string>();
      for (const hub of hubs) {
        const record = hub as Record<string, unknown>;
        if (!boolValue(record.IsPickupPoint ?? record.isPickupPoint)) continue;
        const address = (record.address as Record<string, unknown>) ?? {};
        const cityId = textValue(address.cityTerritoryId ?? record.cityTerritoryId);
        const districtId = textValue(address.districtTerritoryId ?? record.districtTerritoryId);
        const hubId = textValue(record.id ?? record.hubId);
        if (!districtId || !hubId) continue;
        if (cityId && cityId !== wilayaCode) continue;
        if (!hubsByCommune.has(districtId)) {
          hubsByCommune.set(districtId, hubId);
        }
      }
      const enriched = communes.map((c) => {
        const hubId = hubsByCommune.get(c.id) ?? "";
        return {
          ...c,
          has_stop_desk: hubId ? "1" : "0",
          stopdesk_id: hubId,
        };
      });
      await writeCache(
        supabaseAdmin,
        courierKey,
        courierId,
        "commune",
        enriched.map((c) => ({
          remote_id: c.id,
          name_raw: c.name,
          parent_remote_id: c.wilaya_id || wilayaCode,
          wilaya_code: wilayaCode,
          extra: {
            has_stop_desk: c.has_stop_desk,
            stopdesk_id: c.stopdesk_id,
          },
        })),
      );
      return jsonResponse({ ok: true, data: enriched });
    }
  }

  if (isZrExpress) {
    return jsonResponse({ ok: true, data: [] });
  }

  const codes = Array.from(
    new Set([
      wilayaCode,
      wilayaCode.replace(/^0+/, ""),
      wilayaCode.padStart(2, "0"),
    ].filter((v) => v)),
  );
  const { data: rows } = await supabaseAdmin
    .from("communes")
    .select("name_fr, name_ar")
    .in("wilaya_code", codes);
  const fallback = mapDbCommunes(rows ?? []);
  await writeCache(
    supabaseAdmin,
    courierKey,
    courierId,
    "commune",
    fallback.map((c) => ({
      remote_id: c.name,
      name_raw: c.name,
      parent_remote_id: wilayaCode,
      wilaya_code: wilayaCode,
      extra: {
        has_stop_desk: c.has_stop_desk,
        stopdesk_id: c.stopdesk_id,
      },
    })),
  );
  return jsonResponse({ ok: true, data: fallback });
});
