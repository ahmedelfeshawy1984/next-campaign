import { NextResponse } from 'next/server';
import { familyLoveAdmin } from '@/lib/family-love/supabaseAdmin';
import { generateRefreshToken, hashRefreshToken, signFlJwt } from '@/lib/family-love/jwt';
import { familyLoveEnv } from '@/lib/family-love/env';
import { ACCESS_TOKEN_TTL_SECONDS } from '@/lib/family-love/constants';

interface PairingToken {
  id: string;
  child_profile_id: string;
}

interface ChildProfile {
  id: string;
  family_circle_id: string;
  display_name: string;
  avatar_url: string | null;
}

export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: 'BAD_REQUEST' }, { status: 400 });
  }

  const code = typeof (body as { code?: unknown })?.code === 'string' ? (body as { code: string }).code : '';
  if (!code.trim()) {
    return NextResponse.json({ error: 'BAD_REQUEST' }, { status: 400 });
  }

  const admin = familyLoveAdmin();

  // fl_redeem_pairing_token بقت تدّعي الصف (تحط redeemed_at) في نفس التحديث
  // اللي بيفحص الشروط — تحديث ذري بيمنع سباق طلبين متزامنين بنفس الكود.
  // كود مش صحيح/منتهي بيرجّع صف واحد بس بكل حقوله null (مش صفر صفوف ولا
  // exception — دي طبيعة "SELECT * FROM دالة" في Postgres)، فلازم نفحص حقل
  // فعلي زي id مش بس truthiness الكائن نفسه.
  const { data: pairing, error: pairingError } = await admin
    .rpc('fl_redeem_pairing_token', { p_code: code })
    .single<PairingToken>();

  if (pairingError || !pairing?.id) {
    return NextResponse.json({ error: 'CODE_INVALID_OR_EXPIRED' }, { status: 401 });
  }

  const { data: child, error: childError } = await admin
    .from('child_profiles')
    .select('id, family_circle_id, display_name, avatar_url')
    .eq('id', pairing.child_profile_id)
    .single<ChildProfile>();

  if (childError || !child) {
    return NextResponse.json({ error: 'CHILD_NOT_FOUND' }, { status: 500 });
  }

  const refreshToken = generateRefreshToken();

  const { data: deviceSession, error: sessionError } = await admin
    .from('device_sessions')
    .insert({
      kind: 'child',
      child_profile_id: child.id,
      token_hash: hashRefreshToken(refreshToken),
    })
    .select('id')
    .single<{ id: string }>();

  if (sessionError || !deviceSession) {
    return NextResponse.json({ error: 'SESSION_FAILED' }, { status: 500 });
  }

  await admin.rpc('fl_mark_pairing_token_redeemed', {
    p_token_id: pairing.id,
    p_device_session_id: deviceSession.id,
  });

  const accessToken = signFlJwt(
    { sub: deviceSession.id, fl_kind: 'child', fl_circle: child.family_circle_id },
    familyLoveEnv.jwtSecret,
    ACCESS_TOKEN_TTL_SECONDS
  );

  return NextResponse.json({
    accessToken,
    refreshToken,
    expiresIn: ACCESS_TOKEN_TTL_SECONDS,
    kind: 'child',
    child: { id: child.id, displayName: child.display_name, avatarUrl: child.avatar_url },
  });
}
