-- ============================================================================
--  إصلاح سباق شبيه بسباق كود الربط، لكن في إرسال التذكيرات المجدولة
--
--  cron/dispatch-reminders كانت بتعمل SELECT على alerts (fired_at is null)
--  في خطوة، وبعدين تحدّث كل صف fired_at في خطوة تانية بعد ما تبعت الإشعار —
--  استعلامين منفصلين، مش UPDATE ذري واحد. لو الـ cron اتنادى مرتين متقاربتين
--  (مثلاً خدمة خارجية زي cron-job.org بتضرب نفس الرابط كل دقيقة وطلب سابق
--  لسه شغال)، الاتنين ممكن يقروا نفس التذكير قبل ما أي واحد يعلّمه fired_at
--  — يعني نفس التذكير يوصل مرتين للأهل.
--
--  الحل: fl_claim_due_reminders() بترجّع الصفوف المستحقة و**تعلّمها fired_at
--  في نفس الأمر** (UPDATE ... RETURNING)، بنفس أسلوب fl_redeem_pairing_token
--  في 0007 — MVCC بتاعة Postgres بتضمن كل صف يتم ادّعاؤه مرة واحدة بس.
-- ============================================================================

create or replace function public.fl_claim_due_reminders()
returns setof public.alerts
language sql security definer set search_path = public as $$
  update public.alerts
     set fired_at = now()
   where origin = 'parent_reminder'
     and fired_at is null
     and scheduled_for <= now()
   returning *
$$;

revoke execute on function public.fl_claim_due_reminders() from public, anon, authenticated;
