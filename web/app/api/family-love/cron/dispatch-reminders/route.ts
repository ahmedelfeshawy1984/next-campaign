import { NextResponse } from 'next/server';
import { familyLoveAdmin } from '@/lib/family-love/supabaseAdmin';
import { parentRecipientsForCircle, sendPushToDeviceSessions } from '@/lib/family-love/push';

// هدف Vercel Cron (web/vercel.json). بيدوّر على أي تذكير معاده وصل ولسه ما
// اتبعتش، يبعت Web Push، ويعلّمه fired_at عشان ميتكررش. Vercel Cron بيبعت
// GET افتراضيًا، فمعمول POST وGET سوا.
async function dispatch(): Promise<NextResponse> {
  const admin = familyLoveAdmin();

  const { data: due } = await admin
    .from('alerts')
    .select('id, family_circle_id, payload')
    .eq('origin', 'parent_reminder')
    .is('fired_at', null)
    .lte('scheduled_for', new Date().toISOString());

  const rows = (due ?? []) as Array<{ id: string; family_circle_id: string; payload: { message?: string } }>;

  for (const alert of rows) {
    const recipients = await parentRecipientsForCircle(alert.family_circle_id);
    await sendPushToDeviceSessions(
      recipients.map((r) => r.deviceSessionId),
      { title: 'تذكير ⏰', body: alert.payload?.message ?? 'عندك تذكير', url: '/family-love/reminders' }
    );
    await admin.from('alerts').update({ fired_at: new Date().toISOString() }).eq('id', alert.id);
  }

  return NextResponse.json({ processed: rows.length });
}

export const GET = dispatch;
export const POST = dispatch;
