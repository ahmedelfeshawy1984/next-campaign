'use client';

import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { env, isConfigured } from './env';

// The BROWSER client. Separate from lib/supabase.ts on purpose.
//
// The reading client used by server components holds no session — every
// catalogue read is anonymous and RLS decides what comes back. This one DOES
// hold a session, because artwork upload needs an identity: the storage path is
// `<auth.uid()>/<file>` and the policy compares the first path segment to
// auth.uid(). Without a session there is nowhere legal to write.
//
// The identity is anonymous — signInAnonymously(), no email, no password, no
// account for the customer to create before they can send us a logo. What it
// costs is a row in auth.users per visitor who uploads; the cleanup job sweeps
// the ones that never became an order, and register_upload() caps how many
// files one of them can register in a day.

let cached: SupabaseClient | null = null;

export function browserSupabase(): SupabaseClient {
  if (!isConfigured) {
    throw new Error('Supabase is not configured');
  }
  if (!cached) {
    cached = createClient(env.supabaseUrl, env.supabaseAnonKey, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        storageKey: 'nc-auth',
      },
    });
  }
  return cached;
}

/**
 * Returns the current uid, signing in anonymously if there is no session yet.
 *
 * Called lazily — the FIRST time the visitor touches the uploader, not on page
 * load. Creating an auth row for everybody who reads a product page would be
 * rude to their browser and expensive on ours.
 */
export async function ensureSession(): Promise<string> {
  const sb = browserSupabase();

  const { data: existing } = await sb.auth.getSession();
  if (existing.session?.user?.id) return existing.session.user.id;

  const { data, error } = await sb.auth.signInAnonymously();
  if (error) throw error;
  const uid = data.user?.id;
  if (!uid) throw new Error('لم نتمكن من بدء جلسة الرفع');
  return uid;
}
