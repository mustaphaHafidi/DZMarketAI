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

const loadLabelBytes = async (labelValue: string) => {
  const trimmed = labelValue.trim();
  if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
    const resp = await fetch(trimmed);
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

  const lowerCourier = `${courierId} ${courierName}`.toLowerCase();
  const isYalidine = lowerCourier.includes("yalidine");
  const isEcotrack = lowerCourier.includes("ecotrack");

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
    const weight = numberValue(pick(selection, "weight"), 1);
    const height = numberValue(pick(selection, "height"), 0);
    const width = numberValue(pick(selection, "width"), 0);
    const length = numberValue(pick(selection, "length"), 0);
    const declaredValue = numberValue(pick(selection, "declaredValue"), price);
    const freeShipping =
      pick(selection, "freeshipping") === true ||
      textValue(pick(selection, "freeshipping")).toLowerCase() === "true";
    const isStopdesk =
      pick(selection, "deliveryType") === "stopdesk" ||
      pick(selection, "is_stopdesk") === true;
    const hasExchange = pick(selection, "hasExchange") === true;
    const orderRef =
      textValue(pick(selection, "order_ref")) || `${orderId}`;

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
        do_insurance: false,
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
    const resp = await fetch("https://api.yalidine.app/v1/parcels/", {
      method: "POST",
      headers: {
        "X-API-ID": textValue(settingsRow?.api_key),
        "X-API-TOKEN": textValue(settingsRow?.api_secret),
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify(payloadYalidine),
    });
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
        userId,
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
  } else if (isEcotrack) {
    if (!selection) {
      return jsonResponse({ ok: false, message: "Missing shipment selection" }, 400);
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
      weight: textValue(pick(selection, "weight")),
    };
    const params = new URLSearchParams(orderPayload);
    const resp = await fetch("https://api.ecotrack.dz/api/v1/create/order", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${textValue(settingsRow?.api_key)}`,
        Accept: "application/json",
      },
      body: params,
    });
    if (!resp.ok) {
      return jsonResponse({ ok: false, message: `Ecotrack ${resp.status}` }, 502);
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
    const labelResp = await fetch(
      `https://api.ecotrack.dz/api/v1/get/order/label?tracking=${encodeURIComponent(trackingNumber)}`,
      {
        headers: {
          Authorization: `Bearer ${textValue(settingsRow?.api_key)}`,
          Accept: "application/pdf,application/json",
        },
      },
    );
    if (!labelResp.ok) {
      return jsonResponse({ ok: false, message: `Label ${labelResp.status}` }, 502);
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
        userId,
        `ecotrack-${trackingNumber}.pdf`,
        bytes,
      );
    } else {
      labelUrl = "";
    }
  }

  const shipmentPayload: Record<string, unknown> = {
    order_id: orderId,
    tracking_number: trackingNumber || null,
    label_url: labelUrl || null,
    status: labelUrl ? "shipped" : "pending",
    carrier: courierName || courierId,
    option: shippingOption || null,
    delivery_mode: deliveryMode || null,
    shipping_cost: shippingCost || null,
    events: labelUrl
      ? [
          {
            title: "Label generated",
            description: "Ready for carrier pickup",
            at: new Date().toISOString(),
          },
        ]
      : [],
  };

  await supabaseUser.from("shipments").upsert(shipmentPayload);
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
  await supabaseUser.from("orders").update(orderUpdate).eq("id", orderId);

  const eventPayload: Record<string, unknown> = {
    text: labelUrl
      ? "Commande validee, bordereau disponible."
      : "Commande validee, bordereau en preparation.",
    status: labelUrl ? "shipped" : "validated",
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
