-- ============================================================================
--  إصلاح سباق (race condition) في استبدال كود ربط الطفل
--
--  fl_redeem_pairing_token() كانت بتعمل SELECT ... FOR UPDATE من غير ما
--  تعلّم الصف "متستهلك" في نفس الخطوة، وعلّمه redeemed لاحقًا في استدعاء
--  fl_mark_pairing_token_redeemed() منفصل. المشكلة: كل استدعاء RPC عبر
--  PostgREST بيجري في ترانزاكشن لوحه — فالـ FOR UPDATE lock بيتفك أول ما
--  fl_redeem_pairing_token() ترجع، قبل ما fl_mark_pairing_token_redeemed()
--  حتى تتنادى. يعني طلبين POST /api/family-love/pairing/redeem بنفس الكود
--  في نفس اللحظة تقريبًا ممكن الاتنين يعدّوا من الفحص الأول قبل ما أي واحد
--  يعلّم الكود متستهلك — استبدال الكود مرتين لجهازين مختلفين.
--
--  الحل: fl_redeem_pairing_token() بقت "تدّعي" الصف فورًا (تحط redeemed_at)
--  في نفس الأمر اللي بيفحص الشروط — UPDATE واحد ذري، مش SELECT FOR UPDATE
--  منفصل عن التحديث. لو طلبين اتسابقوا، MVCC بتاعة Postgres بتضمن واحد بس
--  يلاقي الصف "لسه متاح" (redeemed_at is null) وقت التنفيذ الفعلي.
-- ============================================================================

create or replace function public.fl_redeem_pairing_token(p_code text)
returns public.pairing_tokens
language sql security definer set search_path = public as $$
  update public.pairing_tokens
     set redeemed_at = now()
   where code = upper(trim(p_code))
     and redeemed_at is null
     and expires_at > now()
   returning *
$$;

-- الدالة دي بترجع null (مش صف) لو مفيش تطابق، عشان كده الاستدعاء من الراوت
-- لازم يفحص null بدل ما يعتمد على exception زي قبل — عدّلنا route.ts كمان.

revoke execute on function public.fl_redeem_pairing_token(text) from public, anon, authenticated;

-- fl_mark_pairing_token_redeemed() فضلت زي ما هي — دلوقتي مسؤوليتها بس
-- تسجيل *مين* استبدل الكود (لأغراض التتبع)، مش جزء من حماية "استخدام واحد
-- بس" — الحماية دي بقت بالكامل في التحديث الذري فوق.
