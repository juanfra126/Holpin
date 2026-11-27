import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-holpin-webhook-secret",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  const expectedSecret = Deno.env.get("HOLPIN_WEBHOOK_SECRET");
  if (!expectedSecret || req.headers.get("x-holpin-webhook-secret") !== expectedSecret) {
    return new Response("Unauthorized webhook", { status: 401 });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const vapidPublicKey = Deno.env.get("VAPID_PUBLIC_KEY");
  const vapidPrivateKey = Deno.env.get("VAPID_PRIVATE_KEY");
  const vapidSubject = Deno.env.get("VAPID_SUBJECT");
  if (!supabaseUrl || !serviceRoleKey || !vapidPublicKey || !vapidPrivateKey || !vapidSubject) {
    return new Response("Missing push environment variables", { status: 500 });
  }

  let payload: any;
  try { payload = await req.json(); }
  catch { return new Response("Invalid JSON", { status: 400 }); }

  // Supabase Database Webhook sends { type, table, record, schema, old_record }.
  const message = payload?.record;
  if (payload?.type !== "INSERT" || payload?.table !== "messages" || !message?.to_id) {
    return new Response("Ignored: not a new message", { status: 200 });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const [{ data: subscriptions, error }, { data: sender }] = await Promise.all([
    supabase.from("push_subscriptions").select("endpoint,sub").eq("user_id", message.to_id),
    supabase.from("profiles").select("name,photo").eq("id", message.from_id).maybeSingle(),
  ]);
  if (error) return new Response("Could not read push subscriptions: " + error.message, { status: 500 });
  if (!subscriptions?.length) return new Response("No subscriptions for recipient", { status: 200 });

  webpush.setVapidDetails(vapidSubject, vapidPublicKey, vapidPrivateKey);
  const title = sender?.name || "Nuevo mensaje en Holpin";
  const body = String(message.body || "Tenés un mensaje nuevo").slice(0, 180);
  const notification = JSON.stringify({
    title,
    body,
    icon: new URL("/icon-192.png.jpeg", supabaseUrl).href,
    url: "/?view=mensajes",
    tag: "holpin-message-" + String(message.from_id || "chat"),
  });

  const results = await Promise.allSettled(subscriptions.map(async (row: any) => {
    try {
      await webpush.sendNotification(row.sub, notification, { TTL: 60 * 60 * 24 });
      return "sent";
    } catch (err: any) {
      if (err?.statusCode === 404 || err?.statusCode === 410) {
        await supabase.from("push_subscriptions").delete().eq("endpoint", row.endpoint);
      }
      throw err;
    }
  }));

  const sent = results.filter((x) => x.status === "fulfilled").length;
  const failed = results.length - sent;
  return new Response(JSON.stringify({ sent, failed }), {
    status: 200,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
