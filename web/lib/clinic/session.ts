'use client';

import { clinicSupabase } from './supabase';
import { normalizePhone } from '../phone.js';
import { wipeLocal, setMeta, getMeta } from './localdb';
import { forgetCatalog } from './drugs';
import { pending } from './outbox';
import type { ClinicStaff } from './types';

// الدخول والجلسة.
//
// The phone → synthetic e-mail bridge is public.email_for_phone(), the SAME
// function the shop's admin login uses. Not copied: derived in SQL so the
// domain lives in exactly one place, because the day the two spellings drift
// nobody can sign in and the cause is invisible.
//
// Note `.schema('public')` on that one call. The clinic client is bound to the
// `clinic` schema, so an unqualified rpc() would look for
// clinic.email_for_phone and 404.

export async function clinicSignIn(phone: string, password: string): Promise<void> {
  const sb = clinicSupabase();

  const { data: email, error: mapError } = await sb
    .schema('public')
    .rpc('email_for_phone', { p_phone: normalizePhone(phone) });
  if (mapError) throw new Error('مشكلة في الاتصال بالخادم');

  const { error } = await sb.auth.signInWithPassword({
    email: email as string,
    password,
  });
  if (error) {
    throw new Error(
      error.message.toLowerCase().includes('invalid')
        ? 'الموبايل أو كلمة السر غلط'
        : 'مش قادرين ندخلك دلوقتي — جرّب تاني'
    );
  }
}

/**
 * Sign out, and take the patient data on this device with it.
 *
 * REFUSES while anything is still queued. The clinic laptop is shared — the
 * next person to sit down must not find the last doctor's patient list — but
 * wiping a prescription that never reached the server would destroy a medical
 * record that exists nowhere else. So the queue has to drain first, and the
 * screen says so.
 */
export async function clinicSignOut(force = false): Promise<void> {
  const queued = await pending();
  if (!force && queued.length > 0) {
    throw new Error(`OUTBOX_NOT_EMPTY:${queued.length}`);
  }
  await clinicSupabase().auth.signOut();
  forgetCatalog();
  await wipeLocal();
}

const ME_CACHE = 'me';

/**
 * Who is signed in, and what may they do?
 *
 * Reads clinic.me() from the server when there is a network, and falls back to
 * the last answer stored on the device when there is not. That fallback is a
 * deliberate trust decision and it is defensible for exactly one reason: the
 * patient data this unlocks is ALREADY on this device, in the clear. Refusing
 * to name the user changes nothing about what a thief could read, and it would
 * stop the clinic working during the outage this whole feature exists for.
 *
 * The real lock on a laptop full of patient files is disk encryption and a
 * device PIN, not a token check the device performs on itself.
 */
export async function currentStaff(): Promise<ClinicStaff | null> {
  const sb = clinicSupabase();
  const { data } = await sb.auth.getSession();
  if (!data.session?.user) return null;

  try {
    const { data: me, error } = await sb.rpc('me');
    if (error) throw error;
    if (!me) return null;                       // signed in, but not clinic staff

    await setMeta(ME_CACHE, me);
    return me as ClinicStaff;
  } catch {
    const cached = await getMeta<ClinicStaff>(ME_CACHE);
    return cached ?? null;
  }
}

export const canExamine = (s: ClinicStaff | null): boolean =>
  s?.role === 'doctor' || s?.role === 'director';

export const isDirector = (s: ClinicStaff | null): boolean => s?.role === 'director';

export const ROLE_LABEL: Record<ClinicStaff['role'], string> = {
  doctor: 'دكتور',
  reception: 'استقبال',
  director: 'ديريكتور',
};
