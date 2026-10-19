import { FN_BASE } from "@/lib/supabase-config";

/** Drop-in replacement for supabase.functions.invoke that calls the app's own server routes. */
export async function invokeFn<T = any>(
  name: string,
  opts: { body?: unknown } = {},
): Promise<{ data: T | null; error: Error | null }> {
  try {
    const res = await fetch(`${FN_BASE}/${name}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(opts.body ?? {}),
    });
    const text = await res.text();
    let data: any = null;
    try {
      data = text ? JSON.parse(text) : null;
    } catch {
      data = text;
    }
    if (!res.ok) return { data, error: new Error(data?.error || `HTTP ${res.status}`) };
    return { data, error: null };
  } catch (e) {
    return { data: null, error: e as Error };
  }
}
