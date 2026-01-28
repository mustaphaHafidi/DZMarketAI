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

  return jsonResponse({ ok: true, processed: results.length, results });
});
