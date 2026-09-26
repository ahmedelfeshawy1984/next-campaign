import { NextResponse } from 'next/server';
import { deviceSessionFromRequest } from '@/lib/family-love/authRequest';
import { familyLoveAdmin } from '@/lib/family-love/supabaseAdmin';
import { notifyParentsWithTemplate } from '@/lib/family-love/push';

// "عندي مشكلة في الموبايل" — بطارية أو شبكة، زرار واحد بس عند الطفل زي ما
// اتفقنا في التصميم (أيقونات قليلة وواضحة لطفل صغير).
export async function POST(request: Request) {
  const session = deviceSessionFromRequest(request);
  if (!session || session.fl_kind !== 'child' || !session.fl_circle) {
    return NextResponse.json({ error: 'UNAUTHORIZED' }, { status: 401 });
  }

  let body: unknown = {};
  try {
    body = await request.json();
  } catch {
    // مفيش body — نفترض "battery_low" الافتراضي.
  }
  const eventKey = (body as { eventKey?: string })?.eventKey === 'no_signal' ? 'no_signal' : 'battery_low';

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
    origin: 'child_status',
    payload: { kind: eventKey },
  });

  await notifyParentsWithTemplate(
    session.fl_circle,
    eventKey,
    {},
    eventKey === 'no_signal' ? 'الشبكة ضعيفة عنده، ممكن ماردش بسرعة.' : 'البطارية بتخلص عنده، ممكن ماوصلش لو قفل الموبايل.',
    '/family-love/home'
  );

  return NextResponse.json({ ok: true });
}
