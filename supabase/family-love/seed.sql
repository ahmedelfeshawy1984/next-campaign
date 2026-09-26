-- ============================================================================
--  Family Love — بيانات أولية
--
--  الجزء الأول (قوالب الرسائل) لازم يتشغّل على أي نشرة حقيقية — دي بيانات
--  تشغيل، مش بيانات تجربة. الجزء الثاني (دائرة تجريبية) لتشغيل محلي فقط،
--  ومحاط بشرط "لو مفيش بيانات فعلاً" زي seed.sql بتاع الشوب.
--  آمن يتشغّل أكتر من مرة (on conflict do nothing / do update).
-- ============================================================================

-- ------------------------------------------------------- قوالب الرسائل -----

insert into public.message_templates (family_circle_id, relation_type, event_key, template_text) values
  (null, 'mother',      'location_share', 'ماما، متقلقيش، أنا دلوقتي هنا: {{maps_link}}'),
  (null, 'father',      'location_share', 'بابا، أنا موقعي دلوقتي هنا: {{maps_link}}'),
  (null, 'spouse',      'location_share', 'أنا في الموقع ده دلوقتي: {{maps_link}}'),
  (null, 'grandmother', 'location_share', 'تيتة، اطمني، أنا هنا دلوقتي: {{maps_link}}'),
  (null, 'grandfather', 'location_share', 'جدو، أنا هنا دلوقتي: {{maps_link}}'),
  (null, 'sibling',     'location_share', 'أنا موقعي دلوقتي هنا: {{maps_link}}'),
  (null, 'other',       'location_share', 'أنا موقعي دلوقتي هنا: {{maps_link}}'),

  (null, 'mother',      'sos_call_me', 'ماما محتاجاك، من فضلك اتصلي بيا دلوقتي 🙏'),
  (null, 'father',      'sos_call_me', 'بابا محتاجك، من فضلك اتصل بيا دلوقتي 🙏'),
  (null, 'spouse',      'sos_call_me', 'محتاج/ة أكلمك دلوقتي، من فضلك اتصل بيا 🙏'),
  (null, 'grandmother', 'sos_call_me', 'تيتة محتاجاك، من فضلك اتصلي بيا 🙏'),
  (null, 'grandfather', 'sos_call_me', 'جدو محتاجك، من فضلك اتصل بيا 🙏'),
  (null, 'sibling',     'sos_call_me', 'محتاجك دلوقتي، من فضلك اتصل بيا 🙏'),
  (null, 'other',       'sos_call_me', 'محتاجك دلوقتي، من فضلك اتصل بيا 🙏'),

  (null, 'mother',      'battery_low', 'ماما، البطارية بتخلص عندي، ممكن ماوصلش لو قفل الموبايل.'),
  (null, 'father',      'battery_low', 'بابا، البطارية بتخلص عندي، ممكن ماوصلش لو قفل الموبايل.'),
  (null, 'spouse',      'battery_low', 'البطارية بتخلص عندي، ممكن ماوصلش لو قفل الموبايل.'),
  (null, 'grandmother', 'battery_low', 'تيتة، البطارية بتخلص عندي.'),
  (null, 'grandfather', 'battery_low', 'جدو، البطارية بتخلص عندي.'),
  (null, 'sibling',     'battery_low', 'البطارية بتخلص عندي.'),
  (null, 'other',       'battery_low', 'البطارية بتخلص عندي.'),

  (null, 'mother',      'no_signal', 'ماما، الشبكة ضعيفة عندي، ممكن ماردش بسرعة.'),
  (null, 'father',      'no_signal', 'بابا، الشبكة ضعيفة عندي، ممكن ماردش بسرعة.'),
  (null, 'spouse',      'no_signal', 'الشبكة ضعيفة عندي، ممكن ماردش بسرعة.'),
  (null, 'grandmother', 'no_signal', 'تيتة، الشبكة ضعيفة عندي.'),
  (null, 'grandfather', 'no_signal', 'جدو، الشبكة ضعيفة عندي.'),
  (null, 'sibling',     'no_signal', 'الشبكة ضعيفة عندي.'),
  (null, 'other',       'no_signal', 'الشبكة ضعيفة عندي.')
on conflict do nothing;

-- ------------------------------------------------------- دائرة تجريبية -----
--  محليًا بس، عشان تجرب الشاشات من غير ما تعدّي على OTP حقيقي. بلا تليفون
--  حقيقي (01000000001 مش رقم مصري مستخدم).
do $$
declare
  v_account_id uuid;
  v_circle_id  uuid;
  v_child_id   uuid;
  v_task_id    uuid;
begin
  if exists (select 1 from public.accounts where phone = '01000000001') then
    return;
  end if;

  insert into public.accounts (phone, full_name)
  values ('01000000001', 'أم تجريبية')
  returning id into v_account_id;

  insert into public.family_circles (owner_account_id, name, governorate, city)
  values (v_account_id, 'عيلة تجريبية', 'القاهرة', 'مدينة نصر')
  returning id into v_circle_id;

  insert into public.family_members (family_circle_id, account_id, relation_type, is_owner)
  values (v_circle_id, v_account_id, 'mother', true);

  insert into public.subscriptions (family_circle_id, trial_ends_at)
  select v_circle_id, now() + (select trial_days from public.family_love_settings) * interval '1 day';

  insert into public.child_profiles (family_circle_id, display_name)
  values (v_circle_id, 'يوسف')
  returning id into v_child_id;

  insert into public.tasks (family_circle_id, child_profile_id, title, recurrence_rule, created_by)
  values (v_circle_id, v_child_id, 'رحلة المدرسة', '{"kind":"daily"}'::jsonb, v_account_id)
  returning id into v_task_id;

  insert into public.stations (task_id, order_index, title, icon) values
    (v_task_id, 0, 'خرجت من البيت',   '🏠'),
    (v_task_id, 1, 'وصلت الباص',      '🚌'),
    (v_task_id, 2, 'وصلت المدرسة',    '🏫');
end $$;
