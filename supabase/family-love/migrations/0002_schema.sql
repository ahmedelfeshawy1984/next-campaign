-- ============================================================================
--  Family Love — الجداول
--
--  بلا Supabase Auth (GoTrue) خالص — لا الأب ولا الطفل عندهم مستخدم حقيقي
--  فيه. الهوية كلها عن طريق device_sessions + JWT موقّع بسر المشروع نفسه
--  (auth.uid() بيقرا claim اسمه sub بس، مش شرط يكون فيه صف في auth.users —
--  اتأكدنا من ده بقراءة supabase/migrations/20260810100001_auth_helpers.sql
--  في مشروع الشوب/العيادة قبل ما نبني على الفرضية دي).
-- ============================================================================

create type public.relation_type as enum
  ('mother', 'father', 'spouse', 'grandmother', 'grandfather', 'sibling', 'other');

create type public.device_kind as enum ('parent', 'child');

create type public.occurrence_status as enum ('pending', 'in_progress', 'done', 'skipped');

create type public.alert_origin as enum ('parent_reminder', 'child_sos', 'child_status');

create type public.subscription_status as enum
  ('trialing', 'active', 'past_due', 'expired', 'cancelled');

create type public.subscription_platform as enum ('android_play', 'web');

create type public.ad_scope as enum ('all_egypt', 'governorate', 'city');

-- ---------------------------------------------------------------- accounts --

create table public.accounts (
  id                 uuid primary key default gen_random_uuid(),
  phone              text not null unique,
  full_name          text,
  is_platform_admin  boolean not null default false,
  created_at         timestamptz not null default now()
);

create table public.family_circles (
  id                 uuid primary key default gen_random_uuid(),
  owner_account_id   uuid not null references public.accounts(id) on delete cascade,
  name               text,
  governorate        text,
  city               text,
  created_at         timestamptz not null default now()
);

create table public.family_members (
  id                 uuid primary key default gen_random_uuid(),
  family_circle_id   uuid not null references public.family_circles(id) on delete cascade,
  account_id         uuid not null references public.accounts(id) on delete cascade,
  relation_type      public.relation_type not null default 'other',
  display_name       text,
  is_owner           boolean not null default false,
  created_at         timestamptz not null default now(),
  unique (family_circle_id, account_id)
);

create table public.child_profiles (
  id                 uuid primary key default gen_random_uuid(),
  family_circle_id   uuid not null references public.family_circles(id) on delete cascade,
  display_name       text not null,
  avatar_url         text,
  created_at         timestamptz not null default now()
);

-- ------------------------------------------------------------- الجلسات ------

-- كل صف هنا هو "مستخدم" فعليًا من وجهة نظر PostgREST — id الصف هو الـ sub
-- في الـ JWT. مفيش أي صف هنا يتعمله insert/update من المتصفح مباشرة؛ كله عن
-- طريق مسارات السيرفر (service role) في web/app/api/family-love/**.
create table public.device_sessions (
  id                          uuid primary key default gen_random_uuid(),
  kind                        public.device_kind not null,
  account_id                  uuid references public.accounts(id) on delete cascade,
  child_profile_id            uuid references public.child_profiles(id) on delete cascade,
  token_hash                  text not null,
  created_at                  timestamptz not null default now(),
  last_seen_at                timestamptz not null default now(),
  revoked_at                  timestamptz,
  constraint device_sessions_kind_shape check (
    (kind = 'parent' and account_id is not null and child_profile_id is null) or
    (kind = 'child'  and child_profile_id is not null and account_id is null)
  )
);

create table public.pairing_tokens (
  id                          uuid primary key default gen_random_uuid(),
  child_profile_id            uuid not null references public.child_profiles(id) on delete cascade,
  code                        text not null unique,
  created_by                  uuid not null references public.accounts(id),
  expires_at                  timestamptz not null,
  redeemed_at                 timestamptz,
  redeemed_device_session_id  uuid references public.device_sessions(id),
  created_at                  timestamptz not null default now()
);

-- --------------------------------------------------------- مهام ومحطات ------

create table public.tasks (
  id                 uuid primary key default gen_random_uuid(),
  family_circle_id   uuid not null references public.family_circles(id) on delete cascade,
  child_profile_id   uuid not null references public.child_profiles(id) on delete cascade,
  title              text not null,
  recurrence_rule    jsonb not null,
  starts_on          date not null default current_date,
  ends_on            date,
  is_active          boolean not null default true,
  created_by         uuid not null references public.accounts(id),
  created_at         timestamptz not null default now()
);

create table public.stations (
  id                 uuid primary key default gen_random_uuid(),
  task_id            uuid not null references public.tasks(id) on delete cascade,
  order_index        int not null,
  title              text not null,
  icon               text,
  unique (task_id, order_index)
);

-- "اليوم" الخاص بمهمة معينة — بيتعمله lazy create أول ما حد يقرا لوحة اليوم،
-- مفيش cron بيولّد صفوف مقدمًا.
create table public.task_occurrences (
  id                       uuid primary key default gen_random_uuid(),
  task_id                  uuid not null references public.tasks(id) on delete cascade,
  child_profile_id         uuid not null references public.child_profiles(id) on delete cascade,
  occurrence_date          date not null,
  current_station_index    int not null default 0,
  status                   public.occurrence_status not null default 'pending',
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  unique (task_id, occurrence_date)
);

-- سجل append-only لكل ضغطة "خلصت المحطة دي" — مش بيتقرأ غالبًا، بس بيوثّق
-- مين ضغط وامتى لو حصل خلاف يوم ما.
create table public.station_events (
  id                        uuid primary key default gen_random_uuid(),
  occurrence_id             uuid not null references public.task_occurrences(id) on delete cascade,
  station_index             int not null,
  actor_device_session_id   uuid not null references public.device_sessions(id),
  created_at                timestamptz not null default now()
);

-- ------------------------------------------------------ رسائل وتنبيهات ------

create table public.messages (
  id                    uuid primary key default gen_random_uuid(),
  family_circle_id      uuid not null references public.family_circles(id) on delete cascade,
  sender_member_id      uuid references public.family_members(id),
  sender_child_id       uuid references public.child_profiles(id),
  recipient_member_id   uuid references public.family_members(id),
  body                  text not null,
  created_at            timestamptz not null default now(),
  read_at               timestamptz,
  constraint messages_sender_shape check (
    (sender_member_id is not null) <> (sender_child_id is not null)
  )
);

create table public.alerts (
  id                    uuid primary key default gen_random_uuid(),
  family_circle_id      uuid not null references public.family_circles(id) on delete cascade,
  child_profile_id      uuid references public.child_profiles(id) on delete cascade,
  origin                public.alert_origin not null,
  scheduled_for         timestamptz,
  fired_at              timestamptz,
  payload               jsonb not null default '{}'::jsonb,
  created_by            uuid references public.accounts(id),
  created_at            timestamptz not null default now()
);

-- لقطة موقع واحدة لحظية بس — مفيش أي تتبع مستمر أو صف بيتحدّث، كل ضغطة على
-- "ابعت موقعي الحالي" بتعمل صف جديد.
create table public.location_pings (
  id                    uuid primary key default gen_random_uuid(),
  family_circle_id      uuid not null references public.family_circles(id) on delete cascade,
  child_profile_id      uuid not null references public.child_profiles(id) on delete cascade,
  lat                   double precision not null,
  lng                   double precision not null,
  accuracy_m            double precision,
  created_at            timestamptz not null default now()
);

-- نص الرسالة بيتغيّر حسب صلة القرابة (relation_type) بتاعة كل مستقبل، مش
-- حسب اختيار الطفل — زرار واحد بس عند الطفل، والتخصيص بيحصل وقت الإرسال.
-- family_circle_id = null يعني نص افتراضي على مستوى المنصة كلها.
create table public.message_templates (
  id                  uuid primary key default gen_random_uuid(),
  family_circle_id    uuid references public.family_circles(id) on delete cascade,
  relation_type       public.relation_type not null,
  event_key           text not null,
  template_text       text not null
);

create unique index message_templates_scope_key
  on public.message_templates (
    coalesce(family_circle_id, '00000000-0000-0000-0000-000000000000'::uuid),
    relation_type,
    event_key
  );

create table public.push_subscriptions (
  id                   uuid primary key default gen_random_uuid(),
  device_session_id    uuid not null references public.device_sessions(id) on delete cascade,
  endpoint             text not null unique,
  p256dh               text not null,
  auth                 text not null,
  last_seen_at         timestamptz not null default now(),
  created_at           timestamptz not null default now()
);

-- ------------------------------------------------------- اشتراكات وإعلانات --

create table public.subscriptions (
  id                     uuid primary key default gen_random_uuid(),
  family_circle_id       uuid not null unique references public.family_circles(id) on delete cascade,
  status                 public.subscription_status not null default 'trialing',
  trial_ends_at          timestamptz not null,
  current_period_end     timestamptz,
  platform               public.subscription_platform,
  external_ref           text,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

create table public.ad_creatives (
  id           uuid primary key default gen_random_uuid(),
  image_url    text not null,
  headline     text,
  target_url   text,
  is_active    boolean not null default true,
  starts_at    timestamptz not null default now(),
  ends_at      timestamptz,
  created_at   timestamptz not null default now()
);

create table public.ad_targets (
  id            uuid primary key default gen_random_uuid(),
  creative_id   uuid not null references public.ad_creatives(id) on delete cascade,
  scope         public.ad_scope not null,
  governorate   text,
  city          text,
  constraint ad_targets_scope_shape check (
    (scope = 'all_egypt'   and governorate is null     and city is null) or
    (scope = 'governorate' and governorate is not null and city is null) or
    (scope = 'city'        and city is not null)
  )
);

-- إعدادات عامة صف وحيد بس (id ثابت true) — نفس فكرة singleton settings.
create table public.family_love_settings (
  id          boolean primary key default true,
  trial_days  int not null default 45,
  constraint family_love_settings_singleton check (id)
);

insert into public.family_love_settings (id, trial_days) values (true, 45)
  on conflict (id) do nothing;
