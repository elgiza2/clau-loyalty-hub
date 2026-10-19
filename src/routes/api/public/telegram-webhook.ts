import { createFileRoute } from "@tanstack/react-router";

// Telegram calls this with the secret_token we registered; anything else is rejected.
export const Route = createFileRoute("/api/public/telegram-webhook")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const { webhookSecret } = await import("@/lib/telegram.server");
        if (request.headers.get("x-telegram-bot-api-secret-token") !== (await webhookSecret())) {
          return new Response("forbidden", { status: 403 });
        }
        const update = await request.json().catch(() => null);
        if (update) {
          const { handleUpdate } = await import("@/lib/bot.server");
          const appUrl = new URL(request.url).origin;
          try {
            await handleUpdate(update, appUrl);
          } catch (e) {
            console.error("[bot]", e);
          }
        }
        return new Response("ok");
      },
      // One-time setup: registers this deployment as the bot's webhook.
      GET: async ({ request }) => {
        const url = new URL(request.url);
        const { tg, webhookSecret, botToken } = await import("@/lib/telegram.server");
        if (url.searchParams.get("setup") !== botToken().split(":")[0]) {
          return new Response("forbidden", { status: 403 });
        }
        await tg("setWebhook", {
          url: `${url.origin}/api/public/telegram-webhook`,
          secret_token: await webhookSecret(),
          allowed_updates: ["message", "callback_query", "pre_checkout_query"],
        });
        await tg("setChatMenuButton", { menu_button: { type: "web_app", text: "Clau", web_app: { url: url.origin } } });
        return new Response("webhook set");
      },
    },
  },
});
