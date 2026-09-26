import { NextResponse } from 'next/server';
import { isEgMobile, normalizePhone } from '@/lib/phone.js';
import { getOtpProvider } from '@/lib/family-love/otpProvider';
import { familyLoveAdmin } from '@/lib/family-love/supabaseAdmin';
import { generateRefreshToken, hashRefreshToken, signFlJwt } from '@/lib/family-love/jwt';
import { familyLoveEnv } from '@/lib/family-love/env';
import { ACCESS_TOKEN_TTL_SECONDS } from '@/lib/family-love/constants';

interface Account {
  id: string;
  phone: string;
  full_name: string | null;
}

export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: 'BAD_REQUEST' }, { status: 400 });
  }

  const { phone: rawPhone, code, fullName } = (body ?? {}) as {
    phone?: string;
    code?: string;
    fullName?: string;
  };
  const phone = normalizePhone(rawPhone ?? '');
  if (!isEgMobile(phone) || !code) {
    return NextResponse.json({ error: 'BAD_REQUEST' }, { status: 400 });
  }

  const codeOk = await getOtpProvider().checkCode(phone, code);
  if (!codeOk) {
    return NextResponse.json({ error: 'CODE_INVALID' }, { status: 401 });
  }

  const admin = familyLoveAdmin();

  const { data: account, error: accountError } = await admin
    .rpc('fl_upsert_parent_account', { p_phone: phone, p_full_name: fullName ?? null })
    .single<Account>();

  if (accountError || !account) {
    return NextResponse.json({ error: 'ACCOUNT_FAILED' }, { status: 500 });
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
