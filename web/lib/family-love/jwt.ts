// توقيع/تحقق JWT مخصص لجلسات الأجهزة — بلا Supabase Auth (GoTrue) خالص.
//
// اتأكدنا من قراءة supabase/migrations/20260810100001_auth_helpers.sql إن
// auth.uid() في PostgREST بترجع claim اسمه sub بس، مش شرط يبقى فيه مستخدم
// حقيقي في auth.users. طالما الـ JWT موقّع بسر مشروع Supabase (Settings ->
// API -> JWT Settings) وفيه role: 'authenticated'، RLS بتشتغل عادي.
//
// HS256 بالـ node:crypto مباشرة، بلا مكتبة jsonwebtoken — المستودع أصلاً
// بيتفادى إضافة اعتماديات لسبب بسيط ممكن نعمله بعشر سطور.
import { createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import type { DeviceKind } from './types';

export interface FlJwtPayload {
  sub: string; // device_sessions.id
  role: 'authenticated';
  fl_kind: DeviceKind;
  fl_circle: string | null;
  iat: number;
  exp: number;
}

function base64url(input: string): string {
  return Buffer.from(input, 'utf8').toString('base64url');
}

export function signFlJwt(
  payload: Pick<FlJwtPayload, 'sub' | 'fl_kind' | 'fl_circle'>,
  secret: string,
  ttlSeconds: number
): string {
  const now = Math.floor(Date.now() / 1000);
  const full: FlJwtPayload = { ...payload, role: 'authenticated', iat: now, exp: now + ttlSeconds };
  const headerPart = base64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const payloadPart = base64url(JSON.stringify(full));
  const signingInput = `${headerPart}.${payloadPart}`;
  const signature = createHmac('sha256', secret).update(signingInput).digest('base64url');
  return `${signingInput}.${signature}`;
}

export function verifyFlJwt(token: string, secret: string): FlJwtPayload | null {
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  const [headerPart, payloadPart, signature] = parts;

  const expected = createHmac('sha256', secret).update(`${headerPart}.${payloadPart}`).digest('base64url');
  const a = Buffer.from(signature);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !timingSafeEqual(a, b)) return null;

  let payload: FlJwtPayload;
  try {
    payload = JSON.parse(Buffer.from(payloadPart, 'base64url').toString('utf8'));
  } catch {
    return null;
  }
  if (typeof payload.exp !== 'number' || payload.exp < Math.floor(Date.now() / 1000)) return null;
  return payload;
}

/** توكن تجديد عشوائي (opaque) — بيتخزن عند العميل، وهاشه بس هو المحفوظ في device_sessions.token_hash. */
export function generateRefreshToken(): string {
  return randomBytes(32).toString('base64url');
}

export function hashRefreshToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}
