import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

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

const requireEnv = (key: string) => {
  const value = Deno.env.get(key);
  if (!value) throw new Error(`${key} is not configured`);
  return value;
};

const toString = (value: unknown) =>
  typeof value === "string" ? value.trim() : "";

const toStringArray = (value: unknown) =>
  Array.isArray(value)
    ? value.map((v) => toString(v)).filter((v) => v.length > 0)
    : [];

const DEFAULT_IMAGE_MODELS = [
  "nudity-2.1",
  "weapon",
  "gore-2.0",
  "offensive",
  "text-content",
].join(",");

const DEFAULT_TEXT_CATEGORIES = [
  "profanity",
  "personal",
  "link",
  "drug",
  "weapon",
  "violence",
  "self-harm",
  "extremism",
  "spam",
  "content-trade",
  "money-transaction",
].join(",");

const NUDITY_RAW_THRESHOLD = 0.5;
const NUDITY_PARTIAL_THRESHOLD = 0.85;
const DEFAULT_PROB_THRESHOLD = 0.5;
const MAX_IMAGES = 3;

const checkImage = async (
  apiUser: string,
  apiSecret: string,
  url: string,
  models: string,
) => {
  const params = new URLSearchParams({
    api_user: apiUser,
    api_secret: apiSecret,
    models,
    url,
  });
  const resp = await fetch(
    "https://api.sightengine.com/1.0/check.json",
    {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: params,
    },
  );
  if (!resp.ok) {
    throw new Error(`Image moderation failed: ${resp.status}`);
  }
  const data = await resp.json();
  if (data?.error) {
    throw new Error(data.error?.message || "Image moderation error");
  }
  return data as Record<string, unknown>;
};

const checkText = async (
  apiUser: string,
  apiSecret: string,
  text: string,
  categories: string,
) => {
  const params = new URLSearchParams({
    api_user: apiUser,
    api_secret: apiSecret,
    text,
    lang: "fr,ar",
    categories,
    mode: "rules",
  });
  const resp = await fetch(
    "https://api.sightengine.com/1.0/text/check.json",
    {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: params,
    },
  );
  if (!resp.ok) {
    throw new Error(`Text moderation failed: ${resp.status}`);
  }
  const data = await resp.json();
  if (data?.error) {
    throw new Error(data.error?.message || "Text moderation error");
  }
  return data as Record<string, unknown>;
};

const extractTextFlags = (data: Record<string, unknown>, categories: string) => {
  const flags: string[] = [];
  for (const key of categories.split(",")) {
    const entry = data[key] as { matches?: unknown[] } | undefined;
    if (entry?.matches && Array.isArray(entry.matches) && entry.matches.length) {
      flags.push(key);
    }
  }
  return flags;
};

const extractImageFlags = (data: Record<string, unknown>) => {
  const flags: string[] = [];
  const nudity = data["nudity"] as { raw?: number; partial?: number } | undefined;
  if (nudity) {
    if ((nudity.raw ?? 0) >= NUDITY_RAW_THRESHOLD) {
      flags.push("nudity_raw");
    }
    if ((nudity.partial ?? 0) >= NUDITY_PARTIAL_THRESHOLD) {
      flags.push("nudity_partial");
    }
  }
  const probCheck = (key: string, label: string) => {
    const node = data[key] as { prob?: number } | undefined;
    if ((node?.prob ?? 0) >= DEFAULT_PROB_THRESHOLD) {
      flags.push(label);
    }
  };
  probCheck("weapon", "weapon");
  probCheck("gore", "gore");
  probCheck("offensive", "offensive");
  probCheck("violence", "violence");
  probCheck("self-harm", "self-harm");
  probCheck("text", "text-content");
  return flags;
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const apiUser = requireEnv("SIGHTENGINE_USER");
    const apiSecret = requireEnv("SIGHTENGINE_SECRET");
    const models = Deno.env.get("SIGHTENGINE_MODELS") ?? DEFAULT_IMAGE_MODELS;
    const categories = Deno.env.get("SIGHTENGINE_TEXT_CATEGORIES") ??
      DEFAULT_TEXT_CATEGORIES;
    const body = await req.json().catch(() => ({}));
    const text = toString(body?.text);
    const imageUrls = toStringArray(body?.image_urls).slice(0, MAX_IMAGES);

    if (!text && imageUrls.length === 0) {
      return jsonResponse({ allowed: true, reason: "empty" });
    }

    const reasons: string[] = [];

    if (text) {
      const textResult = await checkText(apiUser, apiSecret, text, categories);
      reasons.push(...extractTextFlags(textResult, categories));
    }

    for (const url of imageUrls) {
      const imageResult = await checkImage(apiUser, apiSecret, url, models);
      reasons.push(...extractImageFlags(imageResult));
    }

    const allowed = reasons.length === 0;
    return jsonResponse({
      allowed,
      action: allowed ? "allow" : "block",
      reason: allowed ? "" : reasons.join(","),
      labels: reasons,
    });
  } catch (error) {
    return jsonResponse(
      { allowed: false, error: String(error?.message ?? error) },
      503,
    );
  }
});
