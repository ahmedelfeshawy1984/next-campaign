// Configuration, read once and checked honestly.
//
// The sibling projects render a "محتاج إعداد" screen when the keys are missing
// rather than an empty shop, because an empty shop looks like a bug in the
// data and a setup screen looks like what it is. Same rule here — see
// components/SetupRequired.tsx and the guard in app/layout.tsx.
//
// The anon key IS in the JavaScript bundle. That is not a leak, it is the
// design: it carries no privileges of its own, RLS is the gate, and every
// write goes through a rate-limited security-definer function. The key that
// must never appear anywhere in this repo is the service-role key.

const PLACEHOLDERS = ['', 'paste-', 'xxxx', 'your-', 'changeme'];

function isPlaceholder(v: string | undefined): boolean {
  if (!v) return true;
  const lower = v.toLowerCase();
  return PLACEHOLDERS.some((p) => p !== '' && lower.startsWith(p));
}

const LOCAL_ORIGIN = 'http://localhost:3000';

/**
 * Turns whatever somebody typed into a dashboard field into a usable origin.
 *
 * THIS FUNCTION EXISTS BECAUSE A MISSING "https://" TOOK DOWN A DEPLOY.
 *
 * `NEXT_PUBLIC_SITE_URL` was set to `next-campaign-web.vercel.app`, which is
 * exactly what Vercel shows you when you go looking for your own address. The
 * value reached `new URL()` in the root layout's metadataBase, threw
 * ERR_INVALID_URL while collecting page data, and failed the entire build — for
 * a scheme.
 *
 * A field a human fills in by copying something off a screen has to survive
 * being filled in the obvious way. Missing scheme is assumed https, a trailing
 * slash is dropped, and anything still unparseable falls back to localhost so
 * the build produces a site with wrong canonical URLs rather than no site.
 */
function toOrigin(raw: string | undefined): string {
  const trimmed = (raw ?? '').trim().replace(/\/+$/, '');
  if (!trimmed) return LOCAL_ORIGIN;

  const withScheme = /^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`;
  try {
    return new URL(withScheme).origin;
  } catch {
    return LOCAL_ORIGIN;
  }
}

export const env = {
  supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL ?? '',
  supabaseAnonKey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? '',
  /** Absolute origin, needed for canonical URLs, OG images and the sitemap. */
  siteUrl: toOrigin(process.env.NEXT_PUBLIC_SITE_URL),
};

export const isConfigured =
  !isPlaceholder(env.supabaseUrl) && !isPlaceholder(env.supabaseAnonKey);

/** Absolute URL for a path — OG tags and sitemaps cannot use relative ones. */
export function absoluteUrl(path: string): string {
  return `${env.siteUrl}${path.startsWith('/') ? path : `/${path}`}`;
}
