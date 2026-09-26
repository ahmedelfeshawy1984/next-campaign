'use client';

// عميل المتصفح — مشروع Family Love الخاص، بمفتاح anon بس (زي باقي المستودع،
// مفيش مفتاح service role هنا خالص). الفرق الجوهري عن عميل الشوب/العيادة: مفيش
// جلسة Supabase Auth حقيقية أبدًا — الـ fetch المخصص بيحقن توكن الجهاز
// (JWT مخصص، من session.ts) في كل طلب، وده اللي auth.uid() بيقراه في RLS.
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { familyLoveEnv, familyLoveIsConfigured } from './env';
import { getAccessToken } from './session';

function create(): SupabaseClient {
  return createClient(familyLoveEnv.supabaseUrl, familyLoveEnv.supabaseAnonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      fetch: async (input, init) => {
        const token = await getAccessToken();
        const headers = new Headers(init?.headers);
        if (token) headers.set('Authorization', `Bearer ${token}`);
        return fetch(input as RequestInfo, { ...init, headers });
      },
    },
  });
}

let cached: SupabaseClient | null = null;

export function familyLoveSupabase(): SupabaseClient {
  if (!familyLoveIsConfigured) {
    throw new Error('Family Love: Supabase is not configured');
  }
  if (!cached) cached = create();
  return cached;
}
