import { createFileRoute } from "@tanstack/react-router";

// Public endpoints used by the Telegram mini app (replacements for the old
// backend functions). Each handler validates its own input; privileged writes
// are limited to what the original app allowed.
async function dispatch(request: Request, name: string) {
  const { handlers } = await import("@/lib/fn-handlers.server");
  const handler = handlers[name];
  if (!handler) return new Response(JSON.stringify({ error: "Not found" }), { status: 404 });
  try {
    return await handler(request);
  } catch (e) {
    console.error(`[fn:${name}]`, e);
    return new Response(JSON.stringify({ error: "Unexpected error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
}

export const Route = createFileRoute("/api/public/fn/$name")({
  server: {
    handlers: {
      GET: ({ request, params }) => dispatch(request, params.name),
      POST: ({ request, params }) => dispatch(request, params.name),
    },
  },
});
