// Server-side replacements for the old backend functions. Each handler takes the
// request and returns a Response. Dispatched from /api/public/fn/$name.
import { Cell } from "@ton/core";
import { z } from "zod";
import { supabaseAdmin } from "@/integrations/supabase/client.server";
import { tg, esc } from "./telegram.server";

const TREASURY = "UQAp1QxnLJ2z44IooUovvtVShw7hJBEdxCRV3RlbCYC3D8qj";

const json = (payload: unknown, status = 200, extra: Record<string, string> = {}) =>
  new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json", ...extra },
  });

const readBody = async (req: Request): Promise<any> => req.json().catch(() => ({}));

async function notifyAdmins(text: string) {
  const { data: admins } = await supabaseAdmin.from("telegram_admins").select("telegram_id");
  await Promise.allSettled(
    (admins ?? []).map((a) => tg("sendMessage", { chat_id: a.telegram_id, text, parse_mode: "HTML" })),
  );
}

// ── TON payments ────────────────────────────────────────────────────────────
const IntentSchema = z.object({
  telegram_id: z.number().int().positive(),
  action: z.enum(["deposit", "wallet_verification", "server", "battle_item", "ai_pro", "custom_server"]),
  amount_ton: z.number().positive().max(100000),
  metadata: z.record(z.string(), z.unknown()).optional().default({}),
});
const DISCOUNTABLE = new Set(["server", "battle_item", "ai_pro", "custom_server"]);

async function createTonPaymentIntent(req: Request) {
  const parsed = IntentSchema.safeParse(await readBody(req));
  if (!parsed.success) return json({ error: "Invalid request" }, 400);
  const d = parsed.data;
  const baseNano = Math.round(d.amount_ton * 1e9);
  let discountPct = 0;
  let discountReason: string | null = null;
  if (DISCOUNTABLE.has(d.action)) {
    const { data: disc } = await supabaseAdmin.rpc("get_payment_discount_for_telegram", { _telegram_id: d.telegram_id });
    const r = (disc ?? {}) as Record<string, unknown>;
    const pct = Number(r.discount_pct ?? 0);
    if (Number.isFinite(pct) && pct > 0) {
      discountPct = Math.min(pct, 50);
      discountReason = r.first_purchase ? "first_purchase" : String(r.tier ?? "tier");
    }
  }
  const amountNano = Math.max(1, Math.round(baseNano * (1 - discountPct / 100)));
  const memo = `clau:${crypto.randomUUID()}`;
  const { data, error } = await supabaseAdmin
    .from("ton_payment_intents")
    .insert({
      telegram_id: d.telegram_id,
      action: d.action,
      amount_nano: amountNano,
      base_amount_nano: baseNano,
      discount_pct: discountPct,
      discount_reason: discountReason,
      memo,
      metadata: d.metadata as never,
    })
    .select("id,memo,expires_at,amount_nano,base_amount_nano,discount_pct,discount_reason")
    .single();
  if (error) {
    console.error("intent insert failed", error.message);
    return json({ error: "Could not prepare payment" }, 500);
  }
  return json({ ...data, amount_ton: amountNano / 1e9, base_amount_ton: baseNano / 1e9 });
}

const VerifySchema = z.object({
  intent_id: z.string().uuid(),
  boc: z.string().min(10).max(100000).nullable().optional(),
  sender: z.string().min(10).max(100).nullable().optional(),
  quick: z.boolean().optional(),
});

function extractComment(input: Record<string, any>) {
  const data = input.msg_data as { text?: string; body?: string } | undefined;
  if (data?.text) {
    try {
      return new TextDecoder().decode(Uint8Array.from(atob(data.text), (c) => c.charCodeAt(0)));
    } catch {
      return data.text;
    }
  }
  if (!data?.body) return "";
  try {
    const slice = Cell.fromBase64(data.body).beginParse();
    if (slice.loadUint(32) !== 0) return "";
    return slice.loadStringTail();
  } catch {
    return "";
  }
}

async function verifyTonTransaction(req: Request) {
  const parsed = VerifySchema.safeParse(await readBody(req));
  if (!parsed.success) return json({ error: "Invalid verification request", verified: false }, 400);
  const { data: intent } = await supabaseAdmin
    .from("ton_payment_intents")
    .select("id,memo,amount_nano,status,expires_at,wallet_address,tx_hash,boc,telegram_id,action")
    .eq("id", parsed.data.intent_id)
    .single();
  if (!intent) return json({ error: "Payment reference not found", verified: false }, 404);
  if (intent.status === "confirmed") return json({ verified: true, tx_hash: intent.tx_hash });
  if (new Date(intent.expires_at).getTime() < Date.now())
    return json({ error: "Payment reference expired", verified: false }, 410);

  await supabaseAdmin
    .from("ton_payment_intents")
    .update({
      boc: parsed.data.boc ?? intent.boc ?? null,
      wallet_address: parsed.data.sender ?? intent.wallet_address ?? null,
      status: "submitted",
    })
    .eq("id", intent.id);

  const attempts = parsed.data.quick ? 2 : 6;
  for (let i = 0; i < attempts; i++) {
    const res = await fetch(
      `https://toncenter.com/api/v2/getTransactions?address=${encodeURIComponent(TREASURY)}&limit=50&archival=true`,
    );
    const payload = (await res.json().catch(() => null)) as any;
    if (res.ok && payload?.ok && Array.isArray(payload.result)) {
      const match = payload.result.find((tx: any) => {
        const input = tx.in_msg;
        if (!input || Number(input.value) < Number(intent.amount_nano)) return false;
        return extractComment(input) === intent.memo;
      });
      if (match) {
        const txHash = String(match.transaction_id?.hash ?? "");
        const { error } = await supabaseAdmin
          .from("ton_payment_intents")
          .update({ status: "confirmed", tx_hash: txHash, confirmed_at: new Date().toISOString(), failure_reason: null })
          .eq("id", intent.id)
          .is("tx_hash", null);
        if (error) return json({ error: "Payment was already used", verified: false }, 409);
        await notifyAdmins(
          `<b>New TON payment</b>\nAmount: <b>${Number(intent.amount_nano) / 1e9} TON</b>\nType: ${esc(String(intent.action))}\nUser: <code>${intent.telegram_id}</code>`,
        );
        return json({ verified: true, tx_hash: txHash });
      }
    }
    if (i < attempts - 1) await new Promise((r) => setTimeout(r, 3000));
  }
  return json({ verified: false, error: "Payment is still confirming. Try again shortly." }, 202);
}

function tonconnectManifest(req: Request) {
  const url = new URL(req.url);
  let origin = process.env["APP_URL"] || url.origin;
  const raw = url.searchParams.get("origin");
  if (raw) {
    try {
      const o = new URL(raw);
      if (o.protocol === "https:" || o.hostname === "localhost") origin = o.origin;
    } catch {
      /* keep default */
    }
  }
  return json(
    { url: origin, name: "Clau", iconUrl: `${origin}/clau-icon.png`, termsOfUseUrl: origin, privacyPolicyUrl: origin },
    200,
    { "Cache-Control": "public, max-age=300", "Access-Control-Allow-Origin": "*" },
  );
}

// ── Telegram Stars invoices ─────────────────────────────────────────────────
const STARS_PRODUCTS: Record<string, { id: string; title: string; description: string; stars: number; usdt: number; aiPro?: boolean }> = {
  ai_pro: { id: "ai_pro", title: "Clau AI Pro — 30 days", description: "Unlimited chat and images for 30 days.", stars: 667, usdt: 0, aiPro: true },
  usdt_5: { id: "usdt_5", title: "5 USDT top-up", description: "Add 5 USDT to your balance.", stars: 334, usdt: 5 },
  usdt_10: { id: "usdt_10", title: "10 USDT top-up", description: "Add 10 USDT to your balance.", stars: 667, usdt: 10 },
  usdt_25: { id: "usdt_25", title: "25 USDT top-up", description: "Add 25 USDT to your balance.", stars: 1667, usdt: 25 },
};
export { STARS_PRODUCTS };
const starsForTon = (priceTon: number) => Math.max(1, Math.round((priceTon * 3.5) / 0.015));

async function telegramBotAction(req: Request) {
  const body = await readBody(req);
  if (body.action !== "starsInvoice") return json({ error: "Unknown action" }, 400);
  const profileId = typeof body.profileId === "string" ? body.profileId : null;
  const telegramId = Number(body.telegramId) || null;
  if (!profileId) return json({ error: "Missing profile" }, 400);

  const requested = String(body.product ?? "");
  let product = STARS_PRODUCTS[requested];
  if (!product && requested === "server") {
    const { data: server } = await supabaseAdmin
      .from("servers")
      .select("id,name,price_ton,is_active")
      .eq("id", String(body.serverId ?? ""))
      .maybeSingle();
    if (!server || !server.is_active) return json({ error: "Server not found" }, 404);
    product = {
      id: `server:${server.id}`,
      title: `${server.name} — mining server`,
      description: `Unlock the ${server.name} mining server.`,
      stars: starsForTon(Number(server.price_ton)),
      usdt: 0,
    };
  }
  if (!product) return json({ error: "Unknown product" }, 400);
  if (telegramId && (requested === "server" || requested === "ai_pro")) {
    const { data: disc } = await supabaseAdmin.rpc("get_payment_discount_for_telegram", { _telegram_id: telegramId });
    const pct = Math.min(Number((disc as any)?.discount_pct ?? 0) || 0, 50);
    if (pct > 0) product = { ...product, stars: Math.max(1, Math.round(product.stars * (1 - pct / 100))) };
  }
  const payload = `${product.id}:${crypto.randomUUID()}`;
  const { error } = await supabaseAdmin
    .from("star_payments")
    .insert({ profile_id: profileId, telegram_id: telegramId, product: product.id, stars: product.stars, payload, status: "pending" });
  if (error) return json({ error: "Could not create invoice" }, 500);
  try {
    const url = await tg<string>("createInvoiceLink", {
      title: product.title.slice(0, 32),
      description: product.description.slice(0, 255),
      payload,
      currency: "XTR",
      prices: [{ label: product.title.slice(0, 32), amount: product.stars }],
    });
    return json({ url, payload, stars: product.stars });
  } catch (e) {
    console.error(e);
    return json({ error: "Could not create invoice" }, 502);
  }
}

// ── AI ──────────────────────────────────────────────────────────────────────
const AIG = "https://ai.gateway.lovable.dev/v1";
const aigHeaders = () => ({
  "Lovable-API-Key": String(process.env["LOVABLE_API_KEY"] ?? ""),
  Authorization: `Bearer ${process.env["LOVABLE_API_KEY"]}`,
  "Content-Type": "application/json",
  "X-Lovable-AIG-SDK": "fetch",
});

async function aiChat(req: Request) {
  const body = await readBody(req);
  const messages = (Array.isArray(body.messages) ? body.messages.slice(-20) : [])
    .filter((m: any) => m && typeof m.content === "string")
    .map((m: any) => ({ role: m.role === "assistant" ? "assistant" : "user", content: m.content }));
  const res = await fetch(`${AIG}/responses`, {
    method: "POST",
    headers: aigHeaders(),
    body: JSON.stringify({
      model: "openai/gpt-6-astra",
      stream: true,
      store: false,
      reasoning: { effort: "low" },
      instructions: "You are Clau AI, a friendly helpful assistant inside the Clau Telegram app.",
      input: messages,
    }),
  });
  if (res.status === 429) return json({ error: "Too many requests, try again shortly." }, 429);
  if (res.status === 402) return json({ error: "AI credits exhausted." }, 402);
  if (!res.ok || !res.body) return json({ error: "AI unavailable" }, 502);
  // Re-emit Responses deltas in the chat-completions SSE shape the page reads.
  const enc = new TextEncoder();
  const dec = new TextDecoder();
  const reader = res.body.getReader();
  const stream = new ReadableStream({
    async start(controller) {
      let buf = "";
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        buf += dec.decode(value, { stream: true });
        let i: number;
        while ((i = buf.indexOf("\n")) >= 0) {
          const line = buf.slice(0, i).trim();
          buf = buf.slice(i + 1);
          if (!line.startsWith("data:")) continue;
          try {
            const ev = JSON.parse(line.slice(5).trim());
            if (ev.type === "response.output_text.delta" && ev.delta) {
              controller.enqueue(enc.encode(`data: ${JSON.stringify({ choices: [{ delta: { content: ev.delta } }] })}\n\n`));
            }
          } catch {
            /* ignore */
          }
        }
      }
      controller.enqueue(enc.encode("data: [DONE]\n\n"));
      controller.close();
    },
  });
  return new Response(stream, { headers: { "Content-Type": "text/event-stream" } });
}

async function aiMedia(req: Request) {
  const body = await readBody(req);
  if (body.kind === "video") return json({ error: "Video generation is not available yet." }, 400);
  const prompt = String(body.prompt ?? "").slice(0, 1000);
  if (!prompt) return json({ error: "Missing prompt" }, 400);
  const res = await fetch(`${AIG}/images/generations`, {
    method: "POST",
    headers: aigHeaders(),
    body: JSON.stringify({ model: "openai/gpt-image-2.5-sunburst", prompt, n: 1 }),
  });
  if (!res.ok) return json({ error: "Image generation failed" }, 502);
  const data = (await res.json()) as any;
  const item = data?.data?.[0];
  const url = item?.url ?? (item?.b64_json ? `data:image/png;base64,${item.b64_json}` : null);
  if (!url) return json({ error: "No image returned" }, 502);
  return json({ url, kind: "image", model: "clau-image" });
}

type PlanId = "free" | "starter" | "pro" | "ultra";
const PLAN_LIMITS: Record<PlanId, { images: number | null; videos: number | null; price: number }> = {
  free: { images: 3, videos: 0, price: 0 },
  starter: { images: null, videos: null, price: 10 },
  pro: { images: null, videos: null, price: 10 },
  ultra: { images: null, videos: null, price: 10 },
};
async function loadSubscription(profileId: string) {
  const { data } = await supabaseAdmin
    .from("ai_subscriptions")
    .select("plan,status,expires_at,images_used,videos_used")
    .eq("profile_id", profileId)
    .maybeSingle();
  if (!data)
    return { plan: "free", status: "none", expires_at: null, images_used: 0, videos_used: 0, images_limit: 3, videos_limit: 0 };
  const expired = data.expires_at ? new Date(data.expires_at).getTime() < Date.now() : true;
  const active = data.status === "active" && !expired;
  const plan = (active ? data.plan : "free") as PlanId;
  const lim = PLAN_LIMITS[plan] ?? PLAN_LIMITS.free;
  return {
    plan,
    status: active ? "active" : "expired",
    expires_at: data.expires_at,
    images_used: data.images_used ?? 0,
    videos_used: data.videos_used ?? 0,
    images_limit: lim.images,
    videos_limit: lim.videos,
  };
}
async function aiSubscription(req: Request) {
  const body = await readBody(req);
  const profileId = typeof body.profileId === "string" ? body.profileId : null;
  if (!profileId) return json({ error: "Missing profile" }, 400);
  if (body.action !== "subscribe") return json(await loadSubscription(profileId));
  const plan = body.plan as PlanId;
  if (!["starter", "pro", "ultra"].includes(plan)) return json({ error: "Invalid plan" }, 400);
  const { error } = await supabaseAdmin.rpc("ai_activate_plan", { _profile_id: profileId, _plan: plan, _price: PLAN_LIMITS[plan].price });
  if (error)
    return json({ error: error.message.includes("insufficient_balance") ? "Not enough USDT balance to activate this plan." : "Could not activate plan" }, 400);
  return json(await loadSubscription(profileId));
}

// Smart offers: the client falls back to a database offer when this fails.
const aiSmartOffer = async () => json({ error: "unavailable" }, 503);

export const handlers: Record<string, (req: Request) => Promise<Response> | Response> = {
  "create-ton-payment-intent": createTonPaymentIntent,
  "verify-ton-transaction": verifyTonTransaction,
  "tonconnect-manifest": tonconnectManifest,
  "telegram-bot": telegramBotAction,
  "ai-chat": aiChat,
  "ai-deapi": aiMedia,
  "ai-media": aiMedia,
  "ai-subscription": aiSubscription,
  "ai-smart-offer": aiSmartOffer,
};
