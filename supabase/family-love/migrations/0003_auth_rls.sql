-- ============================================================================
--  Family Love — هوية الجهاز و RLS
--
--  auth.uid() هنا بيرجع device_sessions.id — مش شرط يبقى فيه GoTrue user.
--  كل دالة predicate هنا SECURITY DEFINER بمسار ثابت، بالضبط زي is_manager()
--  في مشروع الشوب، ولنفس السببين: تفادي التكرار اللانهائي، ومنع أي حد يعمل
--  schema يقلّد الجدول ويجاوب على الدالة بنفسه.
-- ============================================================================

create or replace function public.fl_my_kind()
returns public.device_kind
language sql stable security definer set search_path = public as $$
  select kind from public.device_sessions
   where id = auth.uid() and revoked_at is null
$$;

create or replace function public.fl_my_account_id()
returns uuid
language sql stable security definer set search_path = public as $$
  select account_id from public.device_sessions
   where id = auth.uid() and revoked_at is null
$$;

create or replace function public.fl_my_child_profile_id()
returns uuid
language sql stable security definer set search_path = public as $$
  select child_profile_id from public.device_sessions
   where id = auth.uid() and revoked_at is null
$$;

create or replace function public.fl_is_parent()
returns boolean
language sql stable security definer set search_path = public as $$
  select public.fl_my_kind() = 'parent'
$$;

create or replace function public.fl_my_circle()
returns uuid
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select family_circle_id from public.family_members
      where account_id = public.fl_my_account_id()),
    (select family_circle_id from public.child_profiles
      where id = public.fl_my_child_profile_id())
  )
$$;

create or replace function public.fl_is_platform_admin()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select is_platform_admin from public.accounts where id = public.fl_my_account_id()),
    false
  )
$$;

revoke execute on function public.fl_my_kind()            from public, anon;
revoke execute on function public.fl_my_account_id()       from public, anon;
revoke execute on function public.fl_my_child_profile_id() from public, anon;
revoke execute on function public.fl_is_parent()            from public, anon;
revoke execute on function public.fl_my_circle()             from public, anon;
revoke execute on function public.fl_is_platform_admin()      from public, anon;

grant execute on function public.fl_my_kind()            to authenticated;
grant execute on function public.fl_my_account_id()       to authenticated;
grant execute on function public.fl_my_child_profile_id() to authenticated;
grant execute on function public.fl_is_parent()            to authenticated;
grant execute on function public.fl_my_circle()             to authenticated;
grant execute on function public.fl_is_platform_admin()      to authenticated;

-- ---------------------------------------------------------------- RLS ------

alter table public.accounts             enable row level security;
alter table public.family_circles       enable row level security;
alter table public.family_members       enable row level security;
alter table public.child_profiles       enable row level security;
alter table public.pairing_tokens       enable row level security;
alter table public.device_sessions      enable row level security;
alter table public.tasks                enable row level security;
alter table public.stations             enable row level security;
alter table public.task_occurrences     enable row level security;
alter table public.station_events       enable row level security;
alter table public.messages             enable row level security;
alter table public.alerts               enable row level security;
alter table public.location_pings       enable row level security;
alter table public.message_templates    enable row level security;
alter table public.push_subscriptions   enable row level security;
alter table public.subscriptions        enable row level security;
alter table public.ad_creatives         enable row level security;
alter table public.ad_targets           enable row level security;

-- anon مالوش أي مقبض على الباب خالص — كل التسجيل (OTP/ربط الطفل) بيحصل من
-- مسارات سيرفر بمفتاح service role، مش من المتصفح مباشرة.
revoke all on all tables in schema public from anon;

-- accounts: كل حساب يشوف نفسه بس.
create policy accounts_select_self on public.accounts
  for select using (id = public.fl_my_account_id());
grant select on public.accounts to authenticated;

-- family_circles: أفراد الدائرة (أب/أم أو طفل) يشوفوا دائرتهم بس.
create policy family_circles_select on public.family_circles
  for select using (id = public.fl_my_circle());
grant select on public.family_circles to authenticated;

-- family_members: قراءة لكل أهل الدائرة، كتابة للأب/الأم بس.
create policy family_members_select on public.family_members
  for select using (family_circle_id = public.fl_my_circle());
create policy family_members_write on public.family_members
  for all using (public.fl_is_parent() and family_circle_id = public.fl_my_circle())
  with check (public.fl_is_parent() and family_circle_id = public.fl_my_circle());
grant select, insert, update, delete on public.family_members to authenticated;

-- child_profiles: قراءة لكل الدائرة، كتابة للأب/الأم بس.
create policy child_profiles_select on public.child_profiles
  for select using (family_circle_id = public.fl_my_circle());
create policy child_profiles_write on public.child_profiles
  for all using (public.fl_is_parent() and family_circle_id = public.fl_my_circle())
  with check (public.fl_is_parent() and family_circle_id = public.fl_my_circle());
grant select, insert, update, delete on public.child_profiles to authenticated;

-- pairing_tokens: الأب/الأم بس يشوفوا/يعملوا أكواد لأطفال دائرتهم. الاستبدال
-- (redeem) بيحصل من مسار سيرفر بمفتاح service role، مش من هنا.
create policy pairing_tokens_select on public.pairing_tokens
  for select using (
    public.fl_is_parent() and
    (select family_circle_id from public.child_profiles where id = child_profile_id) = public.fl_my_circle()
  );
grant select on public.pairing_tokens to authenticated;

-- device_sessions: كل جهاز يشوف صفه هو بس.
create policy device_sessions_select_self on public.device_sessions
  for select using (id = auth.uid());
grant select on public.device_sessions to authenticated;

-- tasks/stations: قراءة لكل الدائرة، كتابة للأب/الأم بس.
create policy tasks_select on public.tasks
  for select using (family_circle_id = public.fl_my_circle());
create policy tasks_write on public.tasks
  for all using (public.fl_is_parent() and family_circle_id = public.fl_my_circle())
  with check (public.fl_is_parent() and family_circle_id = public.fl_my_circle());
grant select, insert, update, delete on public.tasks to authenticated;

create policy stations_select on public.stations
  for select using (
    (select family_circle_id from public.tasks where id = task_id) = public.fl_my_circle()
  );
create policy stations_write on public.stations
  for all using (
    public.fl_is_parent() and
    (select family_circle_id from public.tasks where id = task_id) = public.fl_my_circle()
  )
  with check (
    public.fl_is_parent() and
    (select family_circle_id from public.tasks where id = task_id) = public.fl_my_circle()
  );
grant select, insert, update, delete on public.stations to authenticated;

-- task_occurrences: قراءة فقط من المتصفح — التقدّم بيتغيّر بس عن طريق دالة
-- fl_advance_station() (SECURITY DEFINER بتتخطى RLS كمالكة الجدول). عمدًا
-- مفيش أي UPDATE policy هنا، فحتى لو حد جرّب يبعت UPDATE مباشر، RLS بترفضه
-- تلقائيًا لعدم وجود سياسة تسمح بيه.
create policy task_occurrences_select on public.task_occurrences
  for select using (
    (select family_circle_id from public.child_profiles where id = child_profile_id) = public.fl_my_circle()
  );
grant select on public.task_occurrences to authenticated;

create policy station_events_select on public.station_events
  for select using (
    (select cp.family_circle_id from public.task_occurrences occ
       join public.child_profiles cp on cp.id = occ.child_profile_id
      where occ.id = occurrence_id) = public.fl_my_circle()
  );
grant select on public.station_events to authenticated;

-- messages: أي فرد في الدائرة (أب/أم أو طفل) يقرا ويبعت.
create policy messages_select on public.messages
  for select using (family_circle_id = public.fl_my_circle());
create policy messages_insert on public.messages
  for insert with check (family_circle_id = public.fl_my_circle());
grant select, insert on public.messages to authenticated;

-- alerts: قراءة/إنشاء لأي فرد في الدائرة (تذكير من الأب، أو SOS من الطفل).
create policy alerts_select on public.alerts
  for select using (family_circle_id = public.fl_my_circle());
create policy alerts_insert on public.alerts
  for insert with check (family_circle_id = public.fl_my_circle());
grant select, insert on public.alerts to authenticated;

-- location_pings: قراءة لكل الدائرة، لكن الإنشاء بس من جهاز الطفل نفسه عن
-- نفسه — مينفعش جهاز طفل يبعت موقع لطفل تاني، ولا الأب يبعت موقع بدل الطفل.
create policy location_pings_select on public.location_pings
  for select using (family_circle_id = public.fl_my_circle());
create policy location_pings_insert on public.location_pings
  for insert with check (
    family_circle_id = public.fl_my_circle() and
    child_profile_id = public.fl_my_child_profile_id()
  );
grant select, insert on public.location_pings to authenticated;

-- message_templates: قراءة النصوص الافتراضية (family_circle_id فاضية) أو
-- نصوص دائرتك، تعديل الدائرة بس للأب/الأم.
create policy message_templates_select on public.message_templates
  for select using (family_circle_id is null or family_circle_id = public.fl_my_circle());
create policy message_templates_write on public.message_templates
  for all using (public.fl_is_parent() and family_circle_id = public.fl_my_circle())
  with check (public.fl_is_parent() and family_circle_id = public.fl_my_circle());
grant select, insert, update, delete on public.message_templates to authenticated;

-- push_subscriptions: كل جهاز يدير اشتراك الإشعارات بتاعه هو بس.
create policy push_subscriptions_own on public.push_subscriptions
  for all using (device_session_id = auth.uid())
  with check (device_session_id = auth.uid());
grant select, insert, update, delete on public.push_subscriptions to authenticated;

-- subscriptions: قراءة فقط — الكتابة بتحصل من مسارات الدفع (service role) بس.
create policy subscriptions_select on public.subscriptions
  for select using (family_circle_id = public.fl_my_circle());
grant select on public.subscriptions to authenticated;

-- ad_creatives/ad_targets: إدارة المسؤول بس. عرض الإعلان الفعلي للأهل بيحصل
-- عن طريق fl_active_ad() (SECURITY DEFINER)، مش قراءة مباشرة للجدول.
create policy ad_creatives_admin on public.ad_creatives
  for all using (public.fl_is_platform_admin())
  with check (public.fl_is_platform_admin());
grant select, insert, update, delete on public.ad_creatives to authenticated;

create policy ad_targets_admin on public.ad_targets
  for all using (public.fl_is_platform_admin())
  with check (public.fl_is_platform_admin());
grant select, insert, update, delete on public.ad_targets to authenticated;
