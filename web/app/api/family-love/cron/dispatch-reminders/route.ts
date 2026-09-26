import { NextResponse } from 'next/server';
import { familyLoveAdmin } from '@/lib/family-love/supabaseAdmin';
import { parentRecipientsForCircle, sendPushToDeviceSessions } from '@/lib/family-love/push';

// هدف Vercel Cron (web/vercel.json). بيدوّر على أي تذكير معاده وصل ولسه ما
// اتبعتش، يبعت Web Push. Vercel Cron بيبعت GET افتراضيًا، فمعمول POST وGET سوا.
//
// fl_claim_due_reminders() بتـ"ادّعي" الصفوف (تحط fired_at) في نفس الأمر اللي
// بيفحص الشروط — UPDATE ذري واحد، مش SELECT منفصل عن UPDATE لاحق زي قبل. ده
// بيمنع سباق لو الـ cron اتنادى مرتين متقاربتين (خدمة خارجية أو إعادة محاولة)
// من إرسال نفس التذكير مرتين — نفس أسلوب إصلاح فل_redeem_pairing_token.
async function dispatch(): Promise<NextResponse> {
  const admin = familyLoveAdmin();

  const { data: due } = await admin.rpc('fl_claim_due_reminders');
  const rows = (due ?? []) as Array<{ id: string; family_circle_id: string; payload: { message?: string } }>;

  for (const alert of rows) {
    const recipients = await parentRecipientsForCircle(alert.family_circle_id);
    await sendPushToDeviceSessions(
      recipients.map((r) => r.deviceSessionId),
      { title: 'تذكير ⏰', body: alert.payload?.message ?? 'عندك تذكير', url: '/family-love/reminders' }
    );
  }

  return NextResponse.json({ processed: rows.length });
}

export const GET = dispatch;
export const POST = dispatch;
