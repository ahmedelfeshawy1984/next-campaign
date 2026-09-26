import { NextResponse } from 'next/server';
import { isEgMobile, normalizePhone } from '@/lib/phone.js';
import { familyLoveAdmin } from '@/lib/family-love/supabaseAdmin';
import { generateRefreshToken, hashRefreshToken, signFlJwt } from '@/lib/family-love/jwt';
import { familyLoveEnv } from '@/lib/family-love/env';
import { ACCESS_TOKEN_TTL_SECONDS } from '@/lib/family-love/constants';
import { hashPassword, verifyPassword } from '@/lib/family-love/password';

interface FamilyMember {
  id: string;
  account_id: string;
  family_circle_id: string;
}

interface Account {
  id: string;
  password_hash: string | null;
}

// انضمام فرد عيلة مدعو (زوج/جدة/إلخ) — بيجمع خطوتين مع بعض: التحقق من
// الباسورد بتاع رقمه (أو تسجيله لأول مرة)، واستبدال كود الدعوة، عشان يبقى
// بالظبط طلب واحد من الواجهة.
export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: 'BAD_REQUEST' }, { status: 400 });
  }

  const { code, phone: rawPhone, password, fullName } = (body ?? {}) as {
    code?: string;
    phone?: string;
    password?: string;
    fullName?: string;
  };

  const phone = normalizePhone(rawPhone ?? '');
  if (!code?.trim() || !isEgMobile(phone) || typeof password !== 'string' || password.length < 6) {
    return NextResponse.json({ error: 'BAD_REQUEST' }, { status: 400 });
  }

  const admin = familyLoveAdmin();

  const { data: existing } = await admin
    .from('accounts')
    .select('id, password_hash')
    .eq('phone', phone)
    .maybeSingle<Account>();

  if (existing && (!existing.password_hash || !verifyPassword(password, existing.password_hash))) {
    return NextResponse.json({ error: 'WRONG_PASSWORD' }, { status: 401 });
  }

  const { data: member, error: memberError } = await admin
    .rpc('fl_redeem_member_invite', {
      p_code: code,
      p_phone: phone,
      p_full_name: fullName ?? null,
      p_password_hash: existing ? null : hashPassword(password),
    })
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
