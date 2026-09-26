import { NextResponse } from 'next/server';
import { deviceSessionFromRequest } from '@/lib/family-love/authRequest';
import { familyLoveAdmin } from '@/lib/family-love/supabaseAdmin';

export async function POST(request: Request) {
  const session = deviceSessionFromRequest(request);
  if (!session) {
    return NextResponse.json({ error: 'UNAUTHORIZED' }, { status: 401 });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: 'BAD_REQUEST' }, { status: 400 });
  }

  const { endpoint, keys } = (body ?? {}) as {
    endpoint?: string;
    keys?: { p256dh?: string; auth?: string };
  };
  if (!endpoint || !keys?.p256dh || !keys?.auth) {
    return NextResponse.json({ error: 'BAD_SUBSCRIPTION' }, { status: 400 });
  }

  const { error } = await familyLoveAdmin()
    .from('push_subscriptions')
    .upsert(
      {
        device_session_id: session.sub,
        endpoint,
        p256dh: keys.p256dh,
        auth: keys.auth,
        last_seen_at: new Date().toISOString(),
      },
      { onConflict: 'endpoint' }
    );

  if (error) {
    return NextResponse.json({ error: 'SAVE_FAILED' }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}
