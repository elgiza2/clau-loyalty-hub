// Clau Telegram bot: /start, admin panel (stats, broadcast, tasks), Stars payments.
import { supabaseAdmin } from "@/integrations/supabase/client.server";
import { tg, esc, botToken } from "./telegram.server";
import { STARS_PRODUCTS } from "./fn-handlers.server";

type Draft = { step?: "title" | "image" | "link" | "broadcast"; title?: string; image_url?: string };

const ADMIN_MENU = {
  inline_keyboard: [
    [{ text: "📊 عدد المستخدمين", callback_data: "adm:stats" }],
    [{ text: "📣 رسالة لكل المستخدمين", callback_data: "adm:broadcast" }],
    [{ text: "➕ إضافة مهمة", callback_data: "adm:addtask" }],
    [{ text: "📋 المهام / مسح", callback_data: "adm:tasks" }],
  ],
};

async function isAdmin(id: number) {
  const { data } = await supabaseAdmin.from("telegram_admins").select("telegram_id").eq("telegram_id", id).maybeSingle();
  return !!data;
}
async function getDraft(id: number): Promise<Draft> {
  const { data } = await supabaseAdmin.from("telegram_task_drafts").select("draft").eq("telegram_id", id).maybeSingle();
  return ((data?.draft as Draft) ?? {}) as Draft;
}
async function setDraft(id: number, draft: Draft | null) {
  if (!draft) {
    await supabaseAdmin.from("telegram_task_drafts").delete().eq("telegram_id", id);
    return;
  }
  await supabaseAdmin
    .from("telegram_task_drafts")
    .upsert({ telegram_id: id, draft: draft as never, updated_at: new Date().toISOString() });
}
const send = (chat_id: number, text: string, extra: Record<string, unknown> = {}) =>
  tg("sendMessage", { chat_id, text, parse_mode: "HTML", ...extra });

async function uploadPhoto(fileId: string): Promise<string> {
  const file = await tg<{ file_path: string }>("getFile", { file_id: fileId });
  const res = await fetch(`https://api.telegram.org/file/bot${botToken()}/${file.file_path}`);
  const bytes = new Uint8Array(await res.arrayBuffer());
  const ext = file.file_path.split(".").pop() || "jpg";
  const path = `tasks/${crypto.randomUUID()}.${ext}`;
  const { error } = await supabaseAdmin.storage
    .from("task-images")
    .upload(path, bytes, { contentType: ext === "png" ? "image/png" : "image/jpeg" });
  if (error) throw error;
  return supabaseAdmin.storage.from("task-images").getPublicUrl(path).data.publicUrl;
}

async function stats(chat: number) {
  const { count: total } = await supabaseAdmin.from("profiles").select("id", { count: "exact", head: true });
  const since = new Date(Date.now() - 86400000).toISOString();
  const { count: today } = await supabaseAdmin
    .from("profiles")
    .select("id", { count: "exact", head: true })
    .gte("created_at", since);
  await send(chat, `📊 <b>المستخدمين</b>\nالإجمالي: <b>${total ?? 0}</b>\nآخر 24 ساعة: <b>${today ?? 0}</b>`, {
    reply_markup: ADMIN_MENU,
  });
}

async function listTasks(chat: number) {
  const { data } = await supabaseAdmin.from("tasks").select("id,title,link").order("created_at", { ascending: false }).limit(30);
  if (!data?.length) return send(chat, "مفيش مهام لسه.", { reply_markup: ADMIN_MENU });
  await send(chat, `📋 <b>المهام (${data.length})</b>\nدوس على مهمة عشان تمسحها:`, {
    reply_markup: {
      inline_keyboard: [
        ...data.map((t) => [{ text: `🗑 ${t.title}`.slice(0, 60), callback_data: `del:${t.id}` }]),
        [{ text: "⬅️ رجوع", callback_data: "adm:menu" }],
      ],
    },
  });
}

async function broadcast(chat: number, fromChat: number, messageId: number) {
  const ids: number[] = [];
  for (let from = 0; ; from += 1000) {
    const { data } = await supabaseAdmin.from("profiles").select("telegram_id").range(from, from + 999);
    if (!data?.length) break;
    ids.push(...data.map((r) => Number(r.telegram_id)).filter(Boolean));
    if (data.length < 1000) break;
  }
  await send(chat, `⏳ بيتبعت لـ ${ids.length} مستخدم...`);
  let ok = 0;
  for (let i = 0; i < ids.length; i += 25) {
    const batch = ids.slice(i, i + 25);
    const r = await Promise.allSettled(
      batch.map((id) => tg("copyMessage", { chat_id: id, from_chat_id: fromChat, message_id: messageId })),
    );
    ok += r.filter((x) => x.status === "fulfilled").length;
    if (i + 25 < ids.length) await new Promise((res) => setTimeout(res, 1000));
  }
  await send(chat, `✅ اتبعت لـ <b>${ok}</b> من ${ids.length}`, { reply_markup: ADMIN_MENU });
}

async function handleCallback(q: any) {
  const from = Number(q.from?.id);
  const chat = Number(q.message?.chat?.id ?? from);
  await tg("answerCallbackQuery", { callback_query_id: q.id }).catch(() => {});
  if (!(await isAdmin(from))) return;
  const data = String(q.data ?? "");
  if (data === "adm:menu") return send(chat, "🛠 <b>لوحة أدمن Clau</b>", { reply_markup: ADMIN_MENU });
  if (data === "adm:stats") return stats(chat);
  if (data === "adm:tasks") return listTasks(chat);
  if (data === "adm:broadcast") {
    await setDraft(from, { step: "broadcast" });
    return send(chat, "📣 ابعت الرسالة اللي عايز تبعتها لكل المستخدمين (نص أو صورة).\nللإلغاء: /cancel");
  }
  if (data === "adm:addtask") {
    await setDraft(from, { step: "title" });
    return send(chat, "➕ <b>مهمة جديدة</b>\n1️⃣ ابعت <b>اسم</b> المهمة.\nللإلغاء: /cancel");
  }
  if (data.startsWith("del:")) {
    await supabaseAdmin.from("user_tasks").delete().eq("task_id", data.slice(4));
    const { error } = await supabaseAdmin.from("tasks").delete().eq("id", data.slice(4));
    await send(chat, error ? "❌ مقدرتش أمسح المهمة." : "🗑 المهمة اتمسحت.");
    return listTasks(chat);
  }
}

async function handleAdminDraft(msg: any, from: number, chat: number): Promise<boolean> {
  const draft = await getDraft(from);
  if (!draft.step) return false;
  const text: string = msg.text ?? "";
  if (draft.step === "broadcast") {
    await setDraft(from, null);
    await broadcast(chat, chat, msg.message_id);
    return true;
  }
  if (draft.step === "title") {
    if (!text.trim()) return send(chat, "ابعت اسم المهمة كنص.").then(() => true);
    await setDraft(from, { step: "image", title: text.trim().slice(0, 120) });
    await send(chat, "2️⃣ تمام. دلوقتي ابعت <b>صورة</b> المهمة.");
    return true;
  }
  if (draft.step === "image") {
    const photo = msg.photo?.[msg.photo.length - 1];
    const doc = msg.document?.mime_type?.startsWith("image/") ? msg.document : null;
    const fileId = photo?.file_id ?? doc?.file_id;
    if (!fileId) return send(chat, "ابعت صورة من فضلك.").then(() => true);
    try {
      const url = await uploadPhoto(fileId);
      await setDraft(from, { ...draft, step: "link", image_url: url });
      await send(chat, "3️⃣ حلو. آخر خطوة: ابعت <b>رابط</b> المهمة.");
    } catch (e) {
      console.error(e);
      await send(chat, "❌ مقدرتش أحفظ الصورة، جرّب تاني.");
    }
    return true;
  }
  if (draft.step === "link") {
    if (!/^https?:\/\/\S+$/i.test(text.trim())) return send(chat, "ابعت رابط صحيح يبدأ بـ https://").then(() => true);
    const { error } = await supabaseAdmin.from("tasks").insert({
      title: draft.title ?? "Task",
      image_url: draft.image_url ?? null,
      link: text.trim(),
      reward_amount: 100,
      reward_type: "siri",
      task_type: "social",
      is_active: true,
    });
    await setDraft(from, null);
    await send(chat, error ? "❌ حصل خطأ في حفظ المهمة." : `✅ المهمة <b>${esc(draft.title ?? "")}</b> اتضافت وظاهرة في التطبيق.`, {
      reply_markup: ADMIN_MENU,
    });
    return true;
  }
  return false;
}

async function handleStarsPayment(msg: any) {
  const sp = msg.successful_payment;
  const payload = String(sp.invoice_payload ?? "");
  const { data: row } = await supabaseAdmin.from("star_payments").select("*").eq("payload", payload).maybeSingle();
  if (!row || row.status === "paid") return;
  const product = String(row.product);
  if (product.startsWith("server:")) {
    const serverId = product.slice(7);
    const { data: server } = await supabaseAdmin.from("servers").select("price_ton").eq("id", serverId).maybeSingle();
    await supabaseAdmin.rpc("purchase_server_for_telegram", {
      _telegram_id: Number(row.telegram_id),
      _server_id: serverId,
      _ton_paid: Number(server?.price_ton ?? 0),
      _wallet_address: null as never,
      _tx_hash: sp.telegram_payment_charge_id ?? null,
    });
  }
  const p = STARS_PRODUCTS[product];
  if (p?.aiPro) await supabaseAdmin.rpc("ai_activate_plan", { _profile_id: String(row.profile_id), _plan: "unlimited", _price: 0 });
  if (p && p.usdt > 0) {
    const { data: prof } = await supabaseAdmin.from("profiles").select("usdt_balance").eq("id", String(row.profile_id)).maybeSingle();
    await supabaseAdmin
      .from("profiles")
      .update({ usdt_balance: Number(prof?.usdt_balance ?? 0) + p.usdt })
      .eq("id", String(row.profile_id));
  }
  await supabaseAdmin
    .from("star_payments")
    .update({ status: "paid", paid_at: new Date().toISOString(), charge_id: sp.telegram_payment_charge_id ?? null, meta: sp })
    .eq("id", row.id);
  await send(msg.chat.id, `✅ Payment received — ${esc(p?.title ?? product)} is now active.`);
}

export async function handleUpdate(update: any, appUrl: string) {
  if (update.callback_query) return handleCallback(update.callback_query);
  if (update.pre_checkout_query) {
    return tg("answerPreCheckoutQuery", { pre_checkout_query_id: update.pre_checkout_query.id, ok: true });
  }
  const msg = update.message;
  if (!msg) return;
  if (msg.successful_payment) return handleStarsPayment(msg);
  const from = Number(msg.from?.id);
  const chat = Number(msg.chat?.id);
  if (msg.chat?.type !== "private") return;
  const text: string = (msg.text ?? "").trim();
  const admin = await isAdmin(from);

  if (text === "/claimadmin") {
    const { count } = await supabaseAdmin.from("telegram_admins").select("telegram_id", { count: "exact", head: true });
    if ((count ?? 0) > 0 && !admin) return send(chat, "في أدمن بالفعل.");
    await supabaseAdmin.from("telegram_admins").upsert({ telegram_id: from });
    return send(chat, "✅ بقيت أدمن Clau.\nاكتب /admin لفتح اللوحة.", { reply_markup: ADMIN_MENU });
  }
  if (admin && text === "/cancel") {
    await setDraft(from, null);
    return send(chat, "اتلغى.", { reply_markup: ADMIN_MENU });
  }
  if (admin && text === "/admin") {
    await setDraft(from, null);
    return send(chat, "🛠 <b>لوحة أدمن Clau</b>", { reply_markup: ADMIN_MENU });
  }
  if (admin && !text.startsWith("/") && (await handleAdminDraft(msg, from, chat))) return;

  if (text.startsWith("/start")) {
    const name = esc(msg.from?.first_name ?? "there");
    return send(chat, `👋 Welcome to <b>Clau</b>, ${name}!\n\nMine, complete tasks, battle and earn rewards.`, {
      reply_markup: { inline_keyboard: [[{ text: "🚀 Open Clau", web_app: { url: appUrl } }]] },
    });
  }
}
