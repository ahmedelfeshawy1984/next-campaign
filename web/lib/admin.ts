'use client';

import { browserSupabase } from './supabase-browser';
import { normalizePhone } from './phone.js';

// لوحة التحكم — كلها في المتصفح، بمفتاح anon، تحت RLS.
//
// There is no service-role key anywhere in this codebase and there must never
// be one: it would sit in a bundle a customer downloads. The panel is the same
// anon key as the shop, and every screen below returns nothing at all unless
// `is_manager()` is true for the signed-in session. The gate is the database,
// not the router.
//
// The router guard in AdminShell is a courtesy — it stops a non-manager staring
// at an empty page — not a security boundary. Deleting it would leak nothing.

export interface AdminSession {
  userId: string;
  fullName: string;
  isManager: boolean;
}

/** Phone + password. The address is synthetic — see email_for_phone() in SQL. */
export async function adminSignIn(phone: string, password: string): Promise<void> {
  const sb = browserSupabase();

  // Built in SQL, not here, so the domain lives in exactly one place. The day
  // the two drift, nobody can sign in and the cause is invisible.
  const { data: email, error: mapError } = await sb.rpc('email_for_phone', {
    p_phone: normalizePhone(phone),
  });
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

export async function adminSignOut(): Promise<void> {
  await browserSupabase().auth.signOut();
}

/**
 * Who is signed in, and are they staff?
 *
 * Reads `profiles` rather than the JWT: the role lives in the database and can
 * be revoked there, while a token keeps whatever it was minted with until it
 * expires.
 */
export async function currentAdmin(): Promise<AdminSession | null> {
  const sb = browserSupabase();
  const { data } = await sb.auth.getSession();
  const user = data.session?.user;
  if (!user) return null;

  const { data: profile } = await sb
    .from('profiles')
    .select('full_name, role, is_active')
    .eq('id', user.id)
    .maybeSingle();

  const row = profile as { full_name: string; role: string; is_active: boolean } | null;
  return {
    userId: user.id,
    fullName: row?.full_name ?? 'مستخدم',
    isManager: row?.role === 'manager' && row?.is_active === true,
  };
}

export interface DashboardCounts {
  new: number;
  awaiting_proof: number;
  in_production: number;
  urgent: number;
  mismatch: number;
  drafts: number;
  no_cover: number;
}

export async function dashboardCounts(): Promise<DashboardCounts | null> {
  const { data } = await browserSupabase().rpc('admin_dashboard');
  return (data as DashboardCounts) ?? null;
}

/**
 * A time-limited link to one customer's artwork.
 *
 * The bucket is private and stays private — a customer's unreleased logo is
 * their property. Five minutes is long enough to click and short enough that a
 * link pasted into a group chat is dead before it travels.
 */
export async function artworkUrl(path: string): Promise<string | null> {
  const { data } = await browserSupabase()
    .storage.from('customer-artwork')
    .createSignedUrl(path, 300);
  return data?.signedUrl ?? null;
}

export async function setOrderStatus(
  id: string,
  status: string,
  note?: string | null,
  reason?: string | null
): Promise<void> {
  const { error } = await browserSupabase().rpc('set_order_status', {
    p_id: id,
    p_status: status,
    p_note: note ?? null,
    p_reason: reason ?? null,
  });
  if (error) throw new Error(adminErrorMessage(error.message));
}

const ADMIN_ERRORS: Record<string, string> = {
  NOT_ALLOWED: 'الصلاحية دي مش متاحة لحسابك.',
  NOT_AUTHORISED: 'الصلاحية دي مش متاحة لحسابك.',
  STATUS_FINAL: 'الطلب في حالة نهائية — مش بيتحرك بعد كده.',
  STATUS_TRANSITION_NOT_ALLOWED: 'الانتقال ده مش مسموح من الحالة الحالية.',
  CANCEL_REASON_REQUIRED: 'اكتب سبب الإلغاء.',
  HAS_HISTORY: 'المنتج ده اتطلب قبل كده — أخفيه بدل ما تمسحه.',
  PHONE_TAKEN: 'الرقم ده مسجّل بحساب تاني.',
  PASSWORD_TOO_SHORT: 'كلمة السر لازم ٦ حروف على الأقل.',
  BAD_PHONE: 'رقم موبايل مصري غير صحيح.',
  NAME_REQUIRED: 'الاسم مطلوب.',
  CANNOT_DISABLE_SELF: 'مش هينفع توقف حسابك بنفسك.',
  LAST_MANAGER: 'ده آخر مدير — لازم يفضل شغّال.',
  PRICING_INCOMPLETE: 'قبل النشر: شريحة سعر عند الحد الأدنى، وطريقة طباعة، ومكان طباعة.',
  PRICE_LADDER_NOT_DESCENDING: 'سعر القطعة لازم ينزل أو يفضل ثابت كل ما الكمية تزيد.',
};

export function adminErrorMessage(raw: string): string {
  for (const [marker, message] of Object.entries(ADMIN_ERRORS)) {
    if (raw.includes(marker)) return message;
  }
  return raw;
}
