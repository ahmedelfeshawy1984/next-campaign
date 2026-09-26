import { NextResponse } from 'next/server';
import { isEgMobile, normalizePhone } from '@/lib/phone.js';
import { getOtpProvider } from '@/lib/family-love/otpProvider';
import { familyLoveAdmin } from '@/lib/family-love/supabaseAdmin';
import { generateRefreshToken, hashRefreshToken, signFlJwt } from '@/lib/family-love/jwt';
import { familyLoveEnv } from '@/lib/family-love/env';
import { ACCESS_TOKEN_TTL_SECONDS } from '@/lib/family-love/constants';

interface FamilyMember {
  id: string;
  account_id: string;
  family_circle_id: string;
}

// انضمام فرد عيلة مدعو (زوج/جدة/إلخ) — بيجمع خطوتين مع بعض: التحقق من الـ
// OTP بتاع رقمه، واستبدال كود الدعوة، عشان يبقى بالظبط طلب واحد من الواجهة.
export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: 'BAD_REQUEST' }, { status: 400 });
  }

  const { code, phone: rawPhone, otpCode, fullName } = (body ?? {}) as {
    code?: string;
    phone?: string;
    otpCode?: string;
    fullName?: string;
  };

  const phone = normalizePhone(rawPhone ?? '');
  if (!code?.trim() || !isEgMobile(phone) || !otpCode) {
    return NextResponse.json({ error: 'BAD_REQUEST' }, { status: 400 });
  }

  const codeOk = await getOtpProvider().checkCode(phone, otpCode);
  if (!codeOk) {
    return NextResponse.json({ error: 'CODE_INVALID' }, { status: 401 });
  }

  const admin = familyLoveAdmin();

  const { data: member, error: memberError } = await admin
    .rpc('fl_redeem_member_invite', { p_code: code, p_phone: phone, p_full_name: fullName ?? null })
    .single<FamilyMember>();

  if (memberError || !member) {
    return NextResponse.json({ error: 'INVITE_INVALID_OR_EXPIRED' }, { status: 401 });
  }

  const refreshToken = generateRefreshToken();

  const { data: deviceSession, error: sessionError } = await admin
    .from('device_sessions')
    .insert({ kind: 'parent', account_id: member.account_id, token_hash: hashRefreshToken(refreshToken) })
    .select('id')
    .single<{ id: string }>();

  if (sessionError || !deviceSession) {
    return NextResponse.json({ error: 'SESSION_FAILED' }, { status: 500 });
  }

  const accessToken = signFlJwt(
    { sub: deviceSession.id, fl_kind: 'parent', fl_circle: member.family_circle_id },
    familyLoveEnv.jwtSecret,
    ACCESS_TOKEN_TTL_SECONDS
  );

  return NextResponse.json({
    accessToken,
    refreshToken,
    expiresIn: ACCESS_TOKEN_TTL_SECONDS,
    kind: 'parent',
  });
}
