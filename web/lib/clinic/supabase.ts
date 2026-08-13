'use client';

import { createClient } from '@supabase/supabase-js';
import { clinicEnv, clinicIsConfigured } from '../env';

// عميل العيادة — مشروعه ومفاتيحه.
//
// A THIRD client, and each of the three exists for a reason the other two
// cannot serve:
//
//   lib/supabase.ts         no session, schema public   — the shop window
//   lib/supabase-browser.ts anonymous session, public   — artwork upload
//   this file               a REAL session, schema clinic
//
// It reads clinicEnv, not env: point NEXT_PUBLIC_CLINIC_SUPABASE_URL at a
// project of the clinic's own and patient records leave the shop's database
// entirely. Unset, it falls back to the shop's project and the clinic keeps
// working exactly as it shipped — see the note in lib/env.ts.
//
// `db.schema` is what makes PostgREST address clinic.* instead of public.*.
// It requires one setup step in the Supabase dashboard —
// Settings → API → Exposed schemas → add `clinic` — and without it every read
// here comes back as a 404 that reads like an empty clinic rather than a
// missing configuration. docs/ابدأ-من-هنا.md says so.
//
// STILL THE ANON KEY. There is no service-role key in this repository and
// there must never be one: it would ship inside a bundle a browser downloads.
// The gate is RLS, and in this schema RLS starts from "anon holds no USAGE at
// all".

// The return type is spelled `ReturnType<typeof create>` rather than
// `SupabaseClient` because `db.schema` changes the client's generic
// parameters, and the shape of those parameters has moved between supabase-js
// releases. Inferring it means an upgrade cannot break this file over a
// type-level detail nothing here depends on.
function create() {
  return createClient(clinicEnv.supabaseUrl, clinicEnv.supabaseAnonKey, {
    db: { schema: 'clinic' },
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      // A SEPARATE storage key from the shop's 'nc-auth'. Sharing one would
      // mean a doctor signing out of the clinic on the practice laptop also
      // signs out whoever was in the shop's admin panel in another tab, and
      // — worse — a visitor's anonymous upload session could overwrite the
      // doctor's.
      storageKey: 'clinic-auth',
    },
    global: {
      // Longer than the shop's 15s. A clinic on a phone tethered to a weak
      // signal is the normal case here, not the exception, and a request that
      // would have succeeded in 20 seconds is better than a spurious failure
      // that pushes a prescription into the outbox.
      fetch: (input, init) =>
        fetch(input as RequestInfo, { ...init, signal: AbortSignal.timeout(20000) }),
    },
  });
}

let cached: ReturnType<typeof create> | null = null;

export function clinicSupabase(): ReturnType<typeof create> {
  if (!clinicIsConfigured) {
    throw new Error('Supabase is not configured');
  }
  if (!cached) cached = create();
  return cached;
}

/** Is the browser online RIGHT NOW? Cheap, and wrong often enough to matter. */
export function isOnline(): boolean {
  return typeof navigator === 'undefined' ? true : navigator.onLine !== false;
}
