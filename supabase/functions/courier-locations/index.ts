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

const zrSearch = async (
  path: string,
  bodies: Array<Record<string, unknown>>,
  headers: Record<string, string>,
) => {
  const baseUrl = "https://api.zrexpress.app";
  for (const body of bodies) {
    const resp = await fetch(`${baseUrl}${path}`, {
      method: "POST",
      headers,
      body: JSON.stringify(body),
    });
    if (!resp.ok) continue;
    const decoded = await resp.json();
    const list = extractList(decoded);
    if (list.length) return list;
  }
  return [];
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

  if (requestType === "wilayas") {
    if (isYalidine && settingsRow.api_secret) {
      const url = "https://api.yalidine.app/v1/wilayas/";
      const resp = await fetch(url, {
        headers: {
          "X-API-ID": textValue(settingsRow.api_key),
          "X-API-TOKEN": textValue(settingsRow.api_secret),
          Accept: "application/json",
        },
      });
      if (resp.ok) {
        const decoded = await resp.json();
        const data = decoded?.data ?? decoded;
        if (Array.isArray(data)) {
          const list = data.map((m) => ({
            id: textValue(m.id),
            code: textValue(m.wilaya_code),
            name: textValue(m.wilaya_name) || textValue(m.name),
          })).filter((m) => m.name);
          return jsonResponse({ ok: true, data: list });
        }
      }
    }

    if (isEcotrack) {
      const url = "https://api.ecotrack.dz/api/v1/get/fees";
      const resp = await fetch(url, {
        headers: {
          Authorization: `Bearer ${textValue(settingsRow.api_key)}`,
          Accept: "application/json",
        },
      });
      if (resp.ok) {
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
              const list = rows.map((r) => ({
                id: textValue(r.code),
                code: textValue(r.code),
                name: textValue(r.name_fr) || textValue(r.name_ar),
              })).filter((m) => m.name);
              return jsonResponse({ ok: true, data: list });
            }
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
        if (mapped.length) return jsonResponse({ ok: true, data: mapped });
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
    return jsonResponse({ ok: true, data: fallback });
  }

  if (isYalidine && settingsRow.api_secret) {
    const url = `https://api.yalidine.app/v1/communes?wilaya_id=${encodeURIComponent(wilayaCode)}`;
    const resp = await fetch(url, {
      headers: {
        "X-API-ID": textValue(settingsRow.api_key),
        "X-API-TOKEN": textValue(settingsRow.api_secret),
        Accept: "application/json",
      },
    });
    if (!resp.ok) {
      return jsonResponse({ ok: false, message: "Yalidine communes failed" }, 502);
    }
    const decoded = await resp.json();
    const data = decoded?.data ?? decoded;
    if (Array.isArray(data)) {
      const list = data.map((m) => ({
        id: textValue(m.id),
        name: textValue(m.commune_name) || textValue(m.name),
        wilaya_id: textValue(m.wilaya_id),
        has_stop_desk: textValue(m.has_stop_desk),
        stopdesk_id: textValue(m.stopdesk_id),
      })).filter((m) => m.name);
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
    for (const code of attempts) {
      const url = `https://api.ecotrack.dz/api/v1/get/communes?wilaya_id=${encodeURIComponent(code)}`;
      const resp = await fetch(url, {
        headers: {
          Authorization: `Bearer ${textValue(settingsRow.api_key)}`,
          Accept: "application/json",
        },
      });
      if (resp.ok) {
        const decoded = await resp.json();
        const data = Array.isArray(decoded) ? decoded : decoded?.data;
        if (Array.isArray(data)) {
          const list = data.map((m) => ({
            id: "",
            name: textValue(m.commune) || textValue(m.name),
            wilaya_id: wilayaCode,
            has_stop_desk: "0",
            stopdesk_id: "",
          })).filter((m) => m.name);
          if (list.length) return jsonResponse({ ok: true, data: list });
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
      const hubs = await zrSearch("/api/v1/hubs/search", hubBodies, headers);
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
  return jsonResponse({ ok: true, data: mapDbCommunes(rows ?? []) });
});
