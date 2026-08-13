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

// ---------------------------------------------------------------- العيادة ----

/**
 * The clinic's own Supabase project — patient records on a database of their
 * own, with none of the shop on it.
 *
 * FALLS BACK to the shop's project when these are not set, and that fallback is
 * deliberate: the clinic shipped inside the shop's project, so an existing
 * deployment must keep working untouched by anyone who never sets these.
 *
 * Setting them is what makes the separation real. Point them at a project
 * installed from supabase/SETUP-CLINIC-ONLY.sql, which carries the clinic and
 * the handful of helpers it needs and nothing else — proved on an empty
 * database by tools/schema-check/clinic.mjs.
 */
export const clinicEnv = {
  supabaseUrl: process.env.NEXT_PUBLIC_CLINIC_SUPABASE_URL || env.supabaseUrl,
  supabaseAnonKey:
    process.env.NEXT_PUBLIC_CLINIC_SUPABASE_ANON_KEY || env.supabaseAnonKey,
};

export const clinicIsConfigured =
  !isPlaceholder(clinicEnv.supabaseUrl) && !isPlaceholder(clinicEnv.supabaseAnonKey);

/**
 * Is the clinic actually on its own database, or still sharing the shop's?
 *
 * Surfaced in the clinic's settings screen rather than kept as a private
 * detail: "where do my patient records live" is a question the person
 * responsible for them should be able to answer by looking, not by trusting
 * that an environment variable was set correctly six months ago.
 */
export const clinicIsSeparate =
  clinicIsConfigured && clinicEnv.supabaseUrl !== env.supabaseUrl;

/**
 * The Supabase project the clinic is actually talking to, e.g. `vamnefvim…`.
 *
 * ⚠ SHOWN ON THE LOGIN SCREEN, BEFORE ANYONE SIGNS IN, and that is the point.
 *
 * Vercel injects environment variables at BUILD time, so saving a new one
 * changes nothing until the next deploy. Setting the clinic's variables and not
 * redeploying leaves a site that looks completely correct and is still reading
 * the old database — and the only symptom is "الموبايل أو كلمة السر غلط",
 * because the account exists in the project nobody is talking to.
 *
 * That failure cost an evening. It is invisible by nature, so the fix is to
 * make it visible: the login screen says which database it reached, and a
 * deploy that did not pick up the new variables says so in words.
 *
 * The ref is not a secret — it is the hostname of every API call the browser
 * already makes.
 */
export const clinicProjectRef = (() => {
  try {
    return new URL(clinicEnv.supabaseUrl).hostname.split('.')[0];
  } catch {
    return '';
  }
})();

/** Absolute URL for a path — OG tags and sitemaps cannot use relative ones. */
export function absoluteUrl(path: string): string {
  return `${env.siteUrl}${path.startsWith('/') ? path : `/${path}`}`;
}
