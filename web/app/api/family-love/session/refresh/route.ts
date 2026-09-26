import { NextResponse } from 'next/server';
import { familyLoveAdmin } from '@/lib/family-love/supabaseAdmin';
import { hashRefreshToken, signFlJwt } from '@/lib/family-love/jwt';
import { familyLoveEnv } from '@/lib/family-love/env';
import { ACCESS_TOKEN_TTL_SECONDS } from '@/lib/family-love/constants';
import type { DeviceKind } from '@/lib/family-love/types';

interface DeviceSession {
  id: string;
  kind: DeviceKind;
  account_id: string | null;
  child_profile_id: string | null;
}

export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: 'BAD_REQUEST' }, { status: 400 });
  }

  const refreshToken =
    typeof (body as { refreshToken?: unknown })?.refreshToken === 'string'
      ? (body as { refreshToken: string }).refreshToken
      : '';
  if (!refreshToken) {
    return NextResponse.json({ error: 'BAD_REQUEST' }, { status: 400 });
  }

  const admin = familyLoveAdmin();

  const { data: session } = await admin
    .from('device_sessions')
    .select('id, kind, account_id, child_profile_id')
    .eq('token_hash', hashRefreshToken(refreshToken))
    .is('revoked_at', null)
    .maybeSingle<DeviceSession>();

  if (!session) {
    return NextResponse.json({ error: 'SESSION_NOT_FOUND' }, { status: 401 });
  }

  let circleId: string | null = null;
  if (session.kind === 'parent' && session.account_id) {
    const { data: member } = await admin
      .from('family_members')
      .select('family_circle_id')
      .eq('account_id', session.account_id)
      .limit(1)
      .maybeSingle<{ family_circle_id: string }>();
    circleId = member?.family_circle_id ?? null;
  } else if (session.kind === 'child' && session.child_profile_id) {
    const { data: child } = await admin
      .from('child_profiles')
      .select('family_circle_id')
      .eq('id', session.child_profile_id)
      .maybeSingle<{ family_circle_id: string }>();
    circleId = child?.family_circle_id ?? null;
  }

  await admin.from('device_sessions').update({ last_seen_at: new Date().toISOString() }).eq('id', session.id);

  const accessToken = signFlJwt(
    { sub: session.id, fl_kind: session.kind, fl_circle: circleId },
    familyLoveEnv.jwtSecret,
    ACCESS_TOKEN_TTL_SECONDS
  );

  return NextResponse.json({ accessToken, expiresIn: ACCESS_TOKEN_TTL_SECONDS });
}
