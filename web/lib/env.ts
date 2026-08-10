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

export const env = {
  supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL ?? '',
  supabaseAnonKey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? '',
  /** Absolute origin, needed for canonical URLs, OG images and the sitemap. */
  siteUrl: (process.env.NEXT_PUBLIC_SITE_URL ?? 'http://localhost:3000').replace(/\/$/, ''),
};

export const isConfigured =
  !isPlaceholder(env.supabaseUrl) && !isPlaceholder(env.supabaseAnonKey);

/** Absolute URL for a path — OG tags and sitemaps cannot use relative ones. */
export function absoluteUrl(path: string): string {
  return `${env.siteUrl}${path.startsWith('/') ? path : `/${path}`}`;
}
