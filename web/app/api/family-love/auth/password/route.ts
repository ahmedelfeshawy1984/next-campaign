import { NextResponse } from 'next/server';
import { isEgMobile, normalizePhone } from '@/lib/phone.js';
import { familyLoveAdmin } from '@/lib/family-love/supabaseAdmin';
import { generateRefreshToken, hashRefreshToken, signFlJwt } from '@/lib/family-love/jwt';
import { familyLoveEnv } from '@/lib/family-love/env';
import { ACCESS_TOKEN_TTL_SECONDS } from '@/lib/family-love/constants';
import { hashPassword, verifyPassword } from '@/lib/family-love/password';

interface Account {
  id: string;
  phone: string;
  full_name: string | null;
  password_hash: string | null;
}

// دخول/تسجيل الأب أو الأم في طلب واحد: رقم مش موجود قبل كده -> يتعمله حساب
// بالباسورد ده، رقم موجود -> لازم الباسورد يطابق اللي متسجل.
export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: 'BAD_REQUEST' }, { status: 400 });
  }

  const { phone: rawPhone, password, fullName } = (body ?? {}) as {
    phone?: string;
    password?: string;
    fullName?: string;
  };
  const phone = normalizePhone(rawPhone ?? '');
  if (!isEgMobile(phone) || typeof password !== 'string' || password.length < 6) {
    return NextResponse.json({ error: 'BAD_REQUEST' }, { status: 400 });
  }

  const admin = familyLoveAdmin();

  const { data: existing } = await admin
    .from('accounts')
    .select('id, phone, full_name, password_hash')
    .eq('phone', phone)
    .maybeSingle<Account>();

  let account: { id: string; phone: string; full_name: string | null };

  if (existing) {
    if (!existing.password_hash || !verifyPassword(password, existing.password_hash)) {
      return NextResponse.json({ error: 'WRONG_PASSWORD' }, { status: 401 });
    }
    account = existing;
  } else {
    const { data: created, error: createError } = await admin
      .rpc('fl_upsert_parent_account', {
        p_phone: phone,
        p_full_name: fullName ?? null,
        p_password_hash: hashPassword(password),
      })
      .single<Account>();
    if (createError || !created) {
      return NextResponse.json({ error: 'ACCOUNT_FAILED' }, { status: 500 });
    }
    account = created;
  }

  const { data: member } = await admin
    .from('family_members')
    .select('family_circle_id')
    .eq('account_id', account.id)
    .limit(1)
    .maybeSingle<{ family_circle_id: string }>();

  const refreshToken = generateRefreshToken();

  const { data: deviceSession, error: sessionError } = await admin
    .from('device_sessions')
    .insert({
      kind: 'parent',
      account_id: account.id,
      token_hash: hashRefreshToken(refreshToken),
    })
    .select('id')
    .single<{ id: string }>();

  if (sessionError || !deviceSession) {
    return NextResponse.json({ error: 'SESSION_FAILED' }, { status: 500 });
  }

  const accessToken = signFlJwt(
    {
      sub: deviceSession.id,
      fl_kind: 'parent',
      fl_circle: member?.family_circle_id ?? null,
    },
    familyLoveEnv.jwtSecret,
    ACCESS_TOKEN_TTL_SECONDS
  );

  return NextResponse.json({
    accessToken,
    refreshToken,
    expiresIn: ACCESS_TOKEN_TTL_SECONDS,
    kind: 'parent',
    account: { id: account.id, phone: account.phone, fullName: account.full_name },
  });
}
