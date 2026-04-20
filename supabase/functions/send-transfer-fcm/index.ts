/**
 * Sends an FCM v1 push when a new row is inserted into `transfers`.
 *
 * Deploy:
 *   supabase functions deploy send-transfer-fcm --no-verify-jwt
 *
 * Secrets (Dashboard → Edge Functions → Secrets):
 *   FCM_PROJECT_ID          Firebase project id (same as GCP project)
 *   FCM_SERVICE_ACCOUNT_JSON Full JSON of a Firebase service account with
 *                            "Firebase Cloud Messaging API Admin" enabled
 *
 * Hook: Supabase Dashboard → Database → Webhooks → Create
 *   Table: transfers   Events: INSERT
 *   HTTP Request: POST https://<ref>.functions.supabase.co/send-transfer-fcm
 *   Headers: Authorization: Bearer <SERVICE_ROLE_KEY>
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { GoogleAuth } from "npm:google-auth-library@9.14.2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  const projectId = Deno.env.get("FCM_PROJECT_ID");
  const saJson = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON");
  if (!projectId || !saJson) {
    return new Response(
      JSON.stringify({ error: "Missing FCM_PROJECT_ID or FCM_SERVICE_ACCOUNT_JSON" }),
      { status: 500, headers: { ...cors, "Content-Type": "application/json" } },
    );
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const record = body.record as Record<string, string> | undefined;
  if (!record?.id || !record?.receiver_id) {
    return new Response(JSON.stringify({ error: "Missing transfer record" }), {
      status: 400,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, serviceKey);

  const { data: receiver, error: rErr } = await supabase
    .from("users")
    .select("fcm_token")
    .eq("id", record.receiver_id)
    .maybeSingle();

  if (rErr) {
    console.error("receiver lookup", rErr);
    return new Response(JSON.stringify({ error: rErr.message }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const token = receiver?.fcm_token as string | undefined;
  if (!token) {
    return new Response(JSON.stringify({ ok: true, skipped: "no_fcm_token" }), {
      status: 200,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  let senderCode = "";
  if (record.sender_id) {
    const { data: sender } = await supabase
      .from("users")
      .select("short_code")
      .eq("id", record.sender_id)
      .maybeSingle();
    senderCode = (sender?.short_code as string) ?? "";
  }

  const auth = new GoogleAuth({
    credentials: JSON.parse(saJson),
    scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
  });
  const client = await auth.getClient();
  const access = await client.getAccessToken();
  if (!access.token) {
    return new Response(JSON.stringify({ error: "No OAuth access token" }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const fcmBody = {
    message: {
      token,
      notification: {
        title: "Incoming transfer",
        body: "Tap to open ZenSend and download your files.",
      },
      data: {
        transfer_id: record.id,
        sender_code: senderCode,
        title: "Incoming transfer",
        body: "Tap to open ZenSend and download your files.",
      },
      android: { priority: "HIGH" as const },
      apns: {
        headers: { "apns-priority": "10" },
        payload: {
          aps: {
            alert: {
              title: "Incoming transfer",
              body: "Tap to open ZenSend and download your files.",
            },
            sound: "default",
            "mutable-content": 1,
          },
        },
      },
    },
  };

  const fcmRes = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${access.token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(fcmBody),
    },
  );

  const text = await fcmRes.text();
  if (!fcmRes.ok) {
    console.error("FCM", fcmRes.status, text);
    return new Response(text, {
      status: 502,
      headers: { ...cors, "Content-Type": "application/plain" },
    });
  }

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { ...cors, "Content-Type": "application/json" },
  });
});
