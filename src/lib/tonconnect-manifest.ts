/**
 * Wallets require a manifest whose `url` matches the opening origin, so the
 * manifest is served by the app itself and mirrors the live origin.
 */
export function resolveTonManifestUrl(): string {
  if (typeof window !== "undefined") {
    const { origin } = window.location;
    return `${origin}/api/public/fn/tonconnect-manifest?origin=${encodeURIComponent(origin)}`;
  }
  return "/api/public/fn/tonconnect-manifest";
}
