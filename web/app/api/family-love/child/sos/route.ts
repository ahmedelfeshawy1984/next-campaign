import { NextResponse } from 'next/server';
import { deviceSessionFromRequest } from '@/lib/family-love/authRequest';
import { familyLoveAdmin } from '@/lib/family-love/supabaseAdmin';
import { notifyParentsWithTemplate } from '@/lib/family-love/push';

export async function POST(request: Request) {
  const session = deviceSessionFromRequest(request);
  if (!session || session.fl_kind !== 'child' || !session.fl_circle) {
    return NextResponse.json({ error: 'UNAUTHORIZED' }, { status: 401 });
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

  await admin.from('alerts').insert({
    family_circle_id: session.fl_circle,
    child_profile_id: device.child_profile_id,
    origin: 'child_sos',
    payload: {},
  });

  await notifyParentsWithTemplate(
    session.fl_circle,
    'sos_call_me',
    {},
    'محتاج/ة أكلمك دلوقتي، من فضلك اتصل بيا 🙏',
    '/family-love/home'
  );

  return NextResponse.json({ ok: true });
}
