// Server-only Telegram Bot API helpers.
export function botToken(): string {
  const t = process.env["TELEGRAM_BOT_TOKEN"];
  if (!t) throw new Error("TELEGRAM_BOT_TOKEN missing");
  return t;
}

export async function tg<T = any>(method: string, payload: Record<string, unknown>): Promise<T> {
  const res = await fetch(`https://api.telegram.org/bot${botToken()}/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  const body = (await res.json().catch(() => ({}))) as any;
  if (!res.ok || body?.ok === false) {
    throw new Error(`Telegram ${method} failed: ${body?.description ?? res.status}`);
  }
  return body.result as T;
}

/** Deterministic webhook secret derived from the bot token (no extra secret needed). */
export async function webhookSecret(): Promise<string> {
  const data = new TextEncoder().encode(`clau-webhook:${botToken()}`);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
    .slice(0, 48);
}

export const esc = (s: string) =>
  s.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
