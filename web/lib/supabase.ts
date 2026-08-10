import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { env, isConfigured } from './env';

// One client, anon key, no session — every read in P1 is the shop window and
// RLS decides what comes back. Auth arrives in P3 with the artwork uploader,
// and that is when @supabase/ssr earns its place; installing it now to hold a
// session nobody has yet would be scaffolding, not architecture.

let cached: SupabaseClient | null = null;

export function supabase(): SupabaseClient {
  if (!isConfigured) {
    // Callers are expected to check isConfigured first and render
    // SetupRequired. Reaching here means a page forgot to, and a clear throw
    // beats a confusing empty grid.
    throw new Error('Supabase is not configured — set NEXT_PUBLIC_SUPABASE_URL and _ANON_KEY');
  }
  if (!cached) {
    cached = createClient(env.supabaseUrl, env.supabaseAnonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: {
        // FAIL FAST. Without a timeout, a database that is unreachable — a
        // wrong URL, a paused project, a network blip during `next build` —
        // makes every page hang until the framework gives up on it, one at a
        // time. Eight seconds is far longer than a healthy query and far
        // shorter than a build that looks frozen.
        fetch: (input, init) =>
          fetch(input as RequestInfo, { ...init, signal: AbortSignal.timeout(8000) }),
      },
    });
  }
  return cached;
}

/** Public URL for an object in the product media bucket. */
export function mediaUrl(path: string | null | undefined): string | null {
  if (!path) return null;
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  return `${env.supabaseUrl}/storage/v1/object/public/product-media/${path}`;
}
