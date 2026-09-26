// إرسال Web Push فعلي — VAPID بس، بلا Firebase (المستودع أصلاً مفيهوش).
// سيرفر بس: مكانه الوحيد web/app/api/family-love/**.
import webpush from 'web-push';
import { familyLoveEnv, familyLovePushIsConfigured } from './env';
import { familyLoveAdmin } from './supabaseAdmin';
import { renderTemplate } from './templates';
import type { MessageEventKey, RelationType } from './types';

let vapidConfigured = false;
function ensureVapidConfigured(): void {
  if (vapidConfigured || !familyLovePushIsConfigured) return;
  webpush.setVapidDetails(familyLoveEnv.vapidSubject, familyLoveEnv.vapidPublicKey, familyLoveEnv.vapidPrivateKey);
  vapidConfigured = true;
}

interface PushPayload {
  title: string;
  body: string;
  url?: string;
}

/**
 * بتبعت لكل push_subscriptions بتاعة الأجهزة دي. اشتراك رجع 404/410 (المتصفح
 * قفل الاشتراك من جهته) بيتحذف عشان مانفضلش نحاول عليه تاني.
 */
export async function sendPushToDeviceSessions(deviceSessionIds: string[], payload: PushPayload): Promise<void> {
  if (!familyLovePushIsConfigured || deviceSessionIds.length === 0) return;
  ensureVapidConfigured();

  const admin = familyLoveAdmin();
  const { data: subs } = await admin
    .from('push_subscriptions')
    .select('id, endpoint, p256dh, auth')
    .in('device_session_id', deviceSessionIds);

  const rows = (subs ?? []) as Array<{ id: string; endpoint: string; p256dh: string; auth: string }>;

  await Promise.all(
    rows.map(async (sub) => {
      try {
        await webpush.sendNotification(
          { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
          JSON.stringify(payload)
        );
      } catch (err) {
        const statusCode = (err as { statusCode?: number }).statusCode;
        if (statusCode === 404 || statusCode === 410) {
          await admin.from('push_subscriptions').delete().eq('id', sub.id);
        }
        // أي فشل تاني (شبكة، مزوّد بطيء) بيتجاهل — مش سبب يوقف باقي المستلمين.
      }
    })
  );
}

interface ParentRecipient {
  deviceSessionId: string;
  relationType: RelationType;
}

/** كل أجهزة الأهل (parent-kind) في الدائرة دي، مع صلة قرابة كل واحد. */
export async function parentRecipientsForCircle(circleId: string): Promise<ParentRecipient[]> {
  const admin = familyLoveAdmin();

  const { data: members } = await admin
    .from('family_members')
    .select('account_id, relation_type')
    .eq('family_circle_id', circleId);

  const relationByAccount = new Map<string, RelationType>();
  for (const m of (members ?? []) as Array<{ account_id: string; relation_type: RelationType }>) {
    relationByAccount.set(m.account_id, m.relation_type);
  }
  const accountIds = [...relationByAccount.keys()];
  if (accountIds.length === 0) return [];

  const { data: sessions } = await admin
    .from('device_sessions')
    .select('id, account_id')
    .in('account_id', accountIds)
    .eq('kind', 'parent')
    .is('revoked_at', null);

  return ((sessions ?? []) as Array<{ id: string; account_id: string }>).map((s) => ({
    deviceSessionId: s.id,
    relationType: relationByAccount.get(s.account_id) ?? 'other',
  }));
}

/** نص القالب لصلة القرابة والحدث دول — نص الدائرة الخاص أولى من الافتراضي العام. */
async function templateFor(circleId: string, relationType: RelationType, eventKey: MessageEventKey): Promise<string | null> {
  const admin = familyLoveAdmin();
  const { data } = await admin
    .from('message_templates')
    .select('template_text, family_circle_id')
    .eq('relation_type', relationType)
    .eq('event_key', eventKey)
    .or(`family_circle_id.eq.${circleId},family_circle_id.is.null`);

  const rows = (data ?? []) as Array<{ template_text: string; family_circle_id: string | null }>;
  return rows.find((r) => r.family_circle_id === circleId)?.template_text ?? rows.find((r) => r.family_circle_id === null)?.template_text ?? null;
}

/**
 * بتبعت لكل أهل الدائرة، كل واحد بنص مخصص حسب صلة قرابته — من حدث واحد بس
 * (الطفل مش بيختار مستقبل بنفسه، زي ما اتفقنا في التصميم).
 */
export async function notifyParentsWithTemplate(
  circleId: string,
  eventKey: MessageEventKey,
  vars: Record<string, string>,
  fallbackBody: string,
  url: string
): Promise<void> {
  const recipients = await parentRecipientsForCircle(circleId);
  if (recipients.length === 0) return;

  const deviceIdsByRelation = new Map<RelationType, string[]>();
  for (const r of recipients) {
    const list = deviceIdsByRelation.get(r.relationType) ?? [];
    list.push(r.deviceSessionId);
    deviceIdsByRelation.set(r.relationType, list);
  }

  await Promise.all(
    [...deviceIdsByRelation.entries()].map(async ([relationType, deviceSessionIds]) => {
      const template = await templateFor(circleId, relationType, eventKey);
      const body = template ? renderTemplate(template, vars) : fallbackBody;
      await sendPushToDeviceSessions(deviceSessionIds, { title: 'عائلتي', body, url });
    })
  );
}
