import { NextResponse } from 'next/server';
import { deviceSessionFromRequest } from '@/lib/family-love/authRequest';
import { familyLoveAdmin } from '@/lib/family-love/supabaseAdmin';
import { notifyParentsWithTemplate } from '@/lib/family-love/push';
import { mapsLink } from '@/lib/family-love/templates';

export async function POST(request: Request) {
  const session = deviceSessionFromRequest(request);
  if (!session || session.fl_kind !== 'child' || !session.fl_circle) {
    return NextResponse.json({ error: 'UNAUTHORIZED' }, { status: 401 });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: 'BAD_REQUEST' }, { status: 400 });
  }

  const { lat, lng, accuracy } = (body ?? {}) as { lat?: number; lng?: number; accuracy?: number };
  if (typeof lat !== 'number' || typeof lng !== 'number') {
    return NextResponse.json({ error: 'BAD_REQUEST' }, { status: 400 });
  }

  const admin = familyLoveAdmin();
  const { data: device } = await admin
    .from('device_sessions')
    .select('child_profile_id')
    .eq('id', session.sub)
    .maybeSingle<{ child_profile_id: string }>();
  if (!device?.child_profile_id) {
    return NextResponse.json({ error: 'NOT_FOUND' }, { status: 404 });
  }

  await admin.from('location_pings').insert({
    family_circle_id: session.fl_circle,
    child_profile_id: device.child_profile_id,
    lat,
    lng,
    accuracy_m: accuracy ?? null,
  });

  await notifyParentsWithTemplate(
    session.fl_circle,
    'location_share',
    { maps_link: mapsLink(lat, lng) },
    `أنا موقعي دلوقتي هنا: ${mapsLink(lat, lng)}`,
    '/family-love/home'
  );

  return NextResponse.json({ ok: true });
}
