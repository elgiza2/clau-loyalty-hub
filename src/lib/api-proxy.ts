// When the app is hosted outside Lovable (e.g. Vercel), privileged API work is
// forwarded to the Lovable-hosted backend, which holds the server secrets.
export async function maybeProxy(request: Request): Promise<Response | null> {
  const origin = process.env["PROXY_API_ORIGIN"];
  if (!origin) return null;
  const url = new URL(request.url);
  const target = `${origin.replace(/\/$/, "")}${url.pathname}${url.search}`;
  const headers = new Headers(request.headers);
  headers.delete("host");
  headers.set("x-forwarded-host", url.host);
  const init: RequestInit = { method: request.method, headers, redirect: "manual" };
  if (request.method !== "GET" && request.method !== "HEAD") init.body = await request.arrayBuffer();
  const res = await fetch(target, init);
  return new Response(res.body, { status: res.status, headers: res.headers });
}
