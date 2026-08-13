-- ============================================================================
-- العيادة — إعداد قاعدة بيانات مستقلة
--
-- GENERATED FILE — do not edit. Edit supabase/migrations/*.sql and re-run
--   node tools/build-clinic-setup.mjs
--
-- الملف ده لمشروع Supabase مخصص للعيادة لوحدها — مفيهوش أي حاجة من المحل.
--
-- HOW TO USE
--   1. اعمل مشروع Supabase جديد للعيادة بس
--   2. Supabase dashboard → SQL Editor → New query
--   3. الزق الملف ده كله → Run
--   4. Settings → API → Exposed schemas → ضيف `clinic`
--
-- Safe to run more than once: every statement is idempotent.
--
-- ⚠  WHAT IS IN HERE AND WHY
--
-- The first section is the small foundation the clinic sits on: the profiles
-- table that staff accounts hang off, the phone and Arabic-folding helpers the
-- search depends on, and the account-creation function with the three GoTrue
-- traps already solved in it.
--
-- Those are NOT copies. They are extracted from the very files the shop
-- installs, so the two deployments can never drift into folding an Arabic name
-- two different ways.
-- ============================================================================

-- ############################################################################
-- ##  الأساس المشترك — مستخرج من ملفات المحل، مش منسوخ
-- ############################################################################

-- ## from 20260810100000_schema.sql

create extension if not exists "pgcrypto";

do $$ begin create type public.user_role as enum ('customer','manager');
exception when duplicate_object then null; end $$;

alter type public.user_role add value if not exists 'customer';
alter type public.user_role add value if not exists 'manager';

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  role       public.user_role not null default 'customer',
  full_name  text not null,
  phone      text unique,
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);

-- ## from 20260810100001_auth_helpers.sql

create or replace function public.my_role()
returns public.user_role
language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.is_manager()
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'manager' and is_active
  )
$$;

-- ---------------------------------------------------------------------------
--  Phone normalisation. Mirrors `normalizePhone` in web/lib/phone.ts, character
--  for character, and the harness asserts the two agree on the same six
--  spellings. If they ever diverge, an order filed from a keyboard typing ٠١٠…
--  cannot be read back on /track by someone typing 010….
-- ---------------------------------------------------------------------------
create or replace function public.normalize_phone(p_raw text)
returns text
language plpgsql immutable as $$
declare v text;
begin
  if p_raw is null then return null; end if;

  -- Arabic-Indic ٠١٢… and Eastern-Arabic ۰۱۲… both reach us from real
  -- keyboards; fold them to ASCII, then keep digits only.
  v := translate(p_raw, '٠١٢٣٤٥٦٧٨٩', '0123456789');
  v := translate(v,     '۰۱۲۳۴۵۶۷۸۹', '0123456789');
  v := regexp_replace(v, '[^0-9]', '', 'g');

  if v like '0020%'                   then v := '0' || substr(v, 5); end if;
  if v like '20%'  and length(v) = 12 then v := '0' || substr(v, 3); end if;
  if length(v) = 10 and v like '1%'   then v := '0' || v;            end if;

  return v;
end $$;

-- Is this a real Egyptian mobile number? 010/011/012/015 are the only four
-- prefixes in service. Used by the order RPC, not by the browser alone —
-- client-side validation is a courtesy, not a gate.
create or replace function public.is_eg_mobile(p_raw text)
returns boolean
language sql immutable as $$
  select public.normalize_phone(p_raw) ~ '^01[0125][0-9]{8}$'
$$;

-- ---------------------------------------------------------------------------
--  Arabic folding, exposed as a function so the search box can fold the term
--  the same way the generated `products.search_key` column folded the data.
--  web/lib/arabic.ts is the third implementation and the harness asserts all
--  three agree.
-- ---------------------------------------------------------------------------
create or replace function public.fold_arabic(p_raw text)
returns text
language sql immutable as $$
  select translate(lower(coalesce(p_raw,'')), 'أإآةىًٌٍَُِّْ', 'اااهي')
$$;

-- ---------------------------------------------------------------------------
--  Mirrors the profiles row for every new auth user.
--
--  Anonymous sessions land here too — that is what signInAnonymously() creates,
--  and every artwork upload needs one. They get role 'customer' and a null
--  phone; 20260810100011_cleanup.sql sweeps the ones that never became an
--  order. Without the coalesce on full_name this trigger raises on every
--  anonymous sign-in and the uploader dies with a message nobody can read.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, role, full_name, phone)
  values (
    new.id,
    coalesce((new.raw_user_meta_data ->> 'role')::public.user_role, 'customer'),
    coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''), 'زائر'),
    nullif(public.normalize_phone(new.raw_user_meta_data ->> 'phone'), '')
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ## from 20260810100006_rls.sql

alter table public.profiles               enable row level security;

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_manager());

-- Escalation is blocked at the column level, not by a policy that could be
-- read as "the row is mine so the role is mine".
revoke update on public.profiles from authenticated;
grant update (full_name) on public.profiles to authenticated;

drop policy if exists profiles_self_update on public.profiles;
create policy profiles_self_update on public.profiles
  for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- ## from 20260810100011_accounts.sql

create or replace function public.email_for_phone(p_phone text)
returns text
language sql immutable as $$
  select public.normalize_phone(p_phone) || '@staff.nextcampaign.app'
$$;

-- ---------------------------------------------------------------------------
--  TRAP 1. GoTrue reads several token columns as NOT NULL even though the
--  schema allows nulls. A row inserted directly into auth.users leaves them
--  null and sign-in then fails with "Database error querying schema" — an
--  error that says nothing about the actual cause.
--
--  The loop is guarded per column so this keeps working on a Supabase release
--  with a different column set, rather than failing on a column that no longer
--  exists.
-- ---------------------------------------------------------------------------
drop function if exists public.fix_auth_user_tokens(uuid);

create or replace function public.fix_auth_user_tokens(p_id uuid)
returns void
language plpgsql security definer set search_path = public, auth as $$
declare c text;
begin
  foreach c in array array[
    'confirmation_token','recovery_token','email_change',
    'email_change_token_new','email_change_token_current',
    'phone_change','phone_change_token','reauthentication_token'
  ] loop
    begin
      execute format(
        'update auth.users set %I = coalesce(%I, %L) where id = $1', c, c, ''
      ) using p_id;
    exception when undefined_column then null;
    end;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
--  The private body. Creates a real Supabase Auth user from a phone number.
--
--  TRAP 2. auth.signUp is deliberately NOT used: it waits on a confirmation
--  e-mail to a mailbox that does not exist, because the address is synthetic.
--
--  TRAP 3. `set search_path = public, extensions` IS LOAD-BEARING. On hosted
--  Supabase, crypt() and gen_salt() live in `extensions`, not `public`.
--  Omitting it produces "function gen_salt(unknown) does not exist" on the live
--  database while every local test passes.
-- ---------------------------------------------------------------------------
create or replace function public.create_account(
  p_phone     text,
  p_full_name text,
  p_password  text,
  p_role      public.user_role
) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id    uuid := gen_random_uuid();
  v_phone text := public.normalize_phone(p_phone);
  v_email text;
  v_name  text := nullif(trim(coalesce(p_full_name, '')), '');
begin
  if v_phone is null or not public.is_eg_mobile(v_phone) then
    raise exception 'BAD_PHONE' using errcode = 'P0001';
  end if;
  if v_name is null then
    raise exception 'NAME_REQUIRED' using errcode = 'P0001';
  end if;
  if length(coalesce(p_password, '')) < 6 then
    raise exception 'PASSWORD_TOO_SHORT' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.profiles where phone = v_phone) then
    raise exception 'PHONE_TAKEN' using errcode = 'P0001';
  end if;

  v_email := public.email_for_phone(v_phone);

  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data
  ) values (
    v_id, '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', v_email,
    crypt(p_password, gen_salt('bf')),
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('full_name', v_name, 'phone', v_phone,
                       'role', p_role::text)
  );

  -- GoTrue looks the identity up before the user; without this row sign-in
  -- fails even though the user exists.
  begin
    insert into auth.identities (
      id, provider_id, user_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    ) values (
      gen_random_uuid(), v_id, v_id,
      jsonb_build_object('sub', v_id::text, 'email', v_email,
                         'email_verified', true),
      'email', now(), now(), now()
    );
  exception when others then null;  -- older schemas without provider_id
  end;

  perform public.fix_auth_user_tokens(v_id);

  -- The on_auth_user_created trigger has already mirrored the profile; this
  -- only matters if the trigger is ever removed.
  insert into public.profiles (id, role, full_name, phone)
  values (v_id, p_role, v_name, v_phone)
  on conflict (id) do update
    set role = excluded.role, full_name = excluded.full_name;

  return v_id;
end $$;

-- ############################################################################
-- ##  العيادة
-- ############################################################################

-- ## 20260812100000_clinic_schema.sql
-- ============================================================================
--  العيادة — الـ schema والجداول
--
--  ⚠  Sorts AFTER 20260810100006_rls.sql. Carries its own grants, in
--     20260812100001_clinic_rls.sql. See the rule in tools/build-setup.mjs.
--
--  WHY A SEPARATE SCHEMA AND NOT A `clinic_` PREFIX IN public
--
--  20260810100006_rls.sql hands `anon` SELECT on the shop window by name, and
--  that list is edited by hand every time a catalogue table is added. Patient
--  diagnoses living one careless `grant select` away from that list is not a
--  risk worth carrying. A separate schema makes the mistake IMPOSSIBLE rather
--  than merely unlikely: `anon` has no USAGE on `clinic`, so no grant inside it
--  can be reached at all.
--
--  It also means the day this clinic wants its own Supabase project, moving it
--  is one `pg_dump -n clinic` rather than an archaeology dig through public.
--
--  ONE EXTRA SETUP STEP, and it is documented in docs/ابدأ-من-هنا.md:
--    Supabase dashboard → Settings → API → Exposed schemas → add `clinic`
--  Without it PostgREST cannot see these tables and the app shows an empty
--  clinic with no error worth reading.
-- ============================================================================

create schema if not exists clinic;

-- Nothing anonymous, ever. Not a policy — a missing USAGE, which is a wall
-- rather than a door with a lock on it.
revoke all on schema clinic from public;
revoke all on schema clinic from anon;
grant usage on schema clinic to authenticated;

-- ---------------------------------------------------------------- enums ----

-- The clinic's roles are the CLINIC's business and live here, deliberately not
-- as new values on public.user_role. Two reasons:
--
--   1. `alter type ... add value` cannot USE the new value in the same
--      transaction that added it unless the type was created there too. This
--      file is pasted into the SQL editor as part of one big script, and a
--      policy referencing 'doctor' would fail on an already-installed database
--      — the exact "works on a fresh install, breaks on an upgrade" trap
--      20260810100000_schema.sql:12 warns about.
--   2. A doctor has no role in the shop. Extending the shop's enum would imply
--      otherwise and invite somebody to check `is_manager()` for a doctor.
do $$ begin create type clinic.staff_role as enum ('doctor','reception','director');
exception when duplicate_object then null; end $$;

-- A visit's journey through the day. `booked` exists before the patient
-- arrives; everything else is physical.
do $$ begin create type clinic.visit_status as enum
  ('booked','waiting','in_room','done','no_show','cancelled');
exception when duplicate_object then null; end $$;

do $$ begin create type clinic.visit_kind as enum ('new','follow_up');
exception when duplicate_object then null; end $$;

-- A clinical record is not a row. `issued` is the point of no return: after
-- it, a correction is a NEW record that points back at this one. Shared by
-- encounters and prescriptions because it is the same rule about the same kind
-- of document. See clinic.freeze_issued_rx() in 20260812100002_clinic_rx.sql.
do $$ begin create type clinic.record_status as enum ('draft','issued','cancelled');
exception when duplicate_object then null; end $$;

do $$ begin create type clinic.pay_method as enum ('cash','instapay','card','other');
exception when duplicate_object then null; end $$;

-- --------------------------------------------------------------- staff ----

-- One row per person who works here, hanging off the profile that already
-- carries their name, phone and password.
--
-- Their public.profiles.role stays 'customer' — meaning "no role in the SHOP".
-- A doctor is not a shop manager and must never see /admin. The clinic role is
-- the one below, and it is the only one any policy in this schema reads.
--
-- ⚠ THIS TABLE COMES BEFORE THE PREDICATES THAT READ IT, and the order is not
--   cosmetic: a `language sql` function is parsed when it is created, so
--   clinic.is_doctor() defined above this point fails with "relation
--   clinic.staff does not exist" on a fresh install.
create table if not exists clinic.staff (
  id            uuid primary key references public.profiles(id) on delete cascade,
  role          clinic.staff_role not null,

  -- How the name is PRINTED, which is not always how it is stored on the
  -- profile: "أحمد الفشاوي" in the staff list, "د. أحمد الفشاوي" on the
  -- prescription.
  display_name  text not null,
  title_ar      text,          -- استشاري / أخصائي
  specialty_ar  text,          -- باطنة وسكر
  syndicate_no  text,          -- رقم النقابة، بيتطبع على الروشتة

  -- The prescription number is built ON THE DEVICE so that a prescription can
  -- be written and printed with no network — see clinic.sync_prescription().
  -- This prefix is what keeps two doctors' offline counters from colliding.
  rx_prefix     text unique,

  signature_url text,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  -- Anyone who writes prescriptions needs a prefix, or their numbering
  -- collides with the next doctor's the first time the internet drops.
  constraint staff_clinician_needs_prefix
    check (role = 'reception' or rx_prefix is not null)
);

drop trigger if exists staff_touch on clinic.staff;
create trigger staff_touch before update on clinic.staff
  for each row execute function public.touch_updated_at();

-- ------------------------------------------------------------- helpers ----

-- Same shape and same reasoning as public.is_manager(): SECURITY DEFINER with
-- a pinned search_path, so a policy ON clinic.staff can ask "what is my role"
-- without recursing through that table's own policy, and so nobody who can
-- create a schema can shadow `staff` and answer the question themselves.

create or replace function clinic.my_role()
returns clinic.staff_role
language sql stable security definer set search_path = clinic, public as $$
  select role from clinic.staff where id = auth.uid() and is_active
$$;

create or replace function clinic.is_doctor()
returns boolean
language sql stable security definer set search_path = clinic, public as $$
  select exists (select 1 from clinic.staff
                  where id = auth.uid() and is_active and role = 'doctor')
$$;

create or replace function clinic.is_director()
returns boolean
language sql stable security definer set search_path = clinic, public as $$
  select exists (select 1 from clinic.staff
                  where id = auth.uid() and is_active and role = 'director')
$$;

create or replace function clinic.is_reception()
returns boolean
language sql stable security definer set search_path = clinic, public as $$
  select exists (select 1 from clinic.staff
                  where id = auth.uid() and is_active and role = 'reception')
$$;

-- Sees patients. The predicate that guards every clinical table — a director
-- examines patients too, so the two are one question, asked once.
create or replace function clinic.is_clinician()
returns boolean
language sql stable security definer set search_path = clinic, public as $$
  select exists (select 1 from clinic.staff
                  where id = auth.uid() and is_active
                    and role in ('doctor','director'))
$$;

-- Works here at all. Reception included — they book, weigh and take money.
create or replace function clinic.is_staff()
returns boolean
language sql stable security definer set search_path = clinic, public as $$
  select exists (select 1 from clinic.staff where id = auth.uid() and is_active)
$$;

-- ------------------------------------------------------------ settings ----

-- One row, same shape as public.site_settings. Unlike that table this one is
-- NOT readable by anon — nothing in this schema is.
create table if not exists clinic.settings (
  id boolean primary key default true check (id),

  clinic_name_ar text not null default 'العيادة',
  address_ar     text,
  phone          text,
  whatsapp_phone text,
  working_hours_ar text,

  -- ---- الطباعة ----
  -- The prescription prints on paper that ALREADY has the clinic's letterhead
  -- on it. These are the millimetres of that letterhead the print must not
  -- write over. They live in the database and not in the stylesheet because
  -- the day the print shop delivers a batch with a taller header, fixing it
  -- has to be a settings screen and not a deploy.
  header_offset_mm numeric(5,1) not null default 35.0
    check (header_offset_mm >= 0 and header_offset_mm <= 148),
  footer_offset_mm numeric(5,1) not null default 20.0
    check (footer_offset_mm >= 0 and footer_offset_mm <= 148),
  margin_x_mm      numeric(5,1) not null default 12.0
    check (margin_x_mm >= 0 and margin_x_mm <= 60),

  -- Plain paper instead of the pre-printed pad: draw the letterhead too. Also
  -- what the lab request sheet uses, which is never pre-printed.
  print_header boolean not null default false,

  -- ---- الفلوس ----
  consult_fee   numeric(10,2) not null default 0 check (consult_fee >= 0),
  follow_up_fee numeric(10,2) not null default 0 check (follow_up_fee >= 0),
  -- Within this many days of a visit, the return is a follow-up and not a new
  -- consultation. The number every receptionist argues about; stored once.
  follow_up_days int not null default 14 check (follow_up_days >= 0),
  currency      text not null default 'ج.م',

  -- Bumped whenever the drug catalogue changes. The device compares its cached
  -- version against this one and pulls only the delta — see
  -- clinic.drug_catalog() in 20260812100005_clinic_catalog.sql.
  drug_catalog_version bigint not null default 1,

  updated_at timestamptz not null default now()
);

drop trigger if exists clinic_settings_touch on clinic.settings;
create trigger clinic_settings_touch before update on clinic.settings
  for each row execute function public.touch_updated_at();

insert into clinic.settings (id) values (true) on conflict (id) do nothing;

-- ------------------------------------------------------------ patients ----

-- The file number a receptionist says out loud. A sequence, not a hash: "ملف
-- ١٤٧" is sayable and "ملف a3f9…" is not.
create sequence if not exists clinic.patient_file_seq start with 1000;

create table if not exists clinic.patients (
  id         uuid primary key default gen_random_uuid(),

  -- NULL until the row reaches the server. A patient registered while the
  -- internet was down has a real id (generated on the device) and no file
  -- number yet; clinic.sync_patient() assigns one on arrival. The alternative
  -- — letting the device invent a file number — produces two patients with
  -- file 148 the first time two devices are offline at once.
  file_no    bigint unique,

  full_name  text not null,
  -- Folded exactly the way web/lib/arabic.js folds the search box's input.
  -- tools/schema-check/verify.mjs asserts the two agree; without that, a
  -- patient filed from a keyboard typing "أحمد" cannot be found by someone
  -- typing "احمد".
  name_key   text generated always as (public.fold_arabic(full_name)) stored,

  phone      text,
  gender     text check (gender in ('male','female')),
  birth_date date,

  address_ar text,

  -- The two fields that change what a doctor is allowed to prescribe. They are
  -- plain text on purpose: a coded allergy list nobody maintains is worse than
  -- a sentence somebody actually wrote. The clinic screen prints this in red
  -- above the prescription builder.
  allergies_ar text,
  chronic_ar   text,

  notes_ar   text,

  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists patients_name_key_idx on clinic.patients (name_key text_pattern_ops);
create index if not exists patients_phone_idx    on clinic.patients (phone);
create index if not exists patients_created_idx  on clinic.patients (created_at desc);

drop trigger if exists patients_touch on clinic.patients;
create trigger patients_touch before update on clinic.patients
  for each row execute function public.touch_updated_at();

-- Phone stored the way public.normalize_phone() stores it everywhere else in
-- this database, so "٠١٠…" typed on an Arabic keyboard and "010…" typed on a
-- Latin one are the same patient.
create or replace function clinic.normalize_patient_phone()
returns trigger language plpgsql set search_path = clinic, public as $$
begin
  new.phone := nullif(public.normalize_phone(new.phone), '');
  return new;
end $$;

drop trigger if exists patients_phone_norm on clinic.patients;
create trigger patients_phone_norm before insert or update of phone on clinic.patients
  for each row execute function clinic.normalize_patient_phone();

-- -------------------------------------------------------------- visits ----

create table if not exists clinic.visits (
  id           uuid primary key default gen_random_uuid(),
  patient_id   uuid not null references clinic.patients(id) on delete cascade,
  doctor_id    uuid references clinic.staff(id) on delete set null,

  scheduled_at timestamptz,
  arrived_at   timestamptz,
  started_at   timestamptz,
  ended_at     timestamptz,

  status       clinic.visit_status not null default 'booked',
  kind         clinic.visit_kind   not null default 'new',

  -- Snapshotted from settings at booking time. Raising the fee next month must
  -- not rewrite what last month's patient was told — the same rule the shop
  -- applies to order lines (20260810100009_orders.sql:8).
  fee          numeric(10,2) not null default 0 check (fee >= 0),

  created_by   uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists visits_patient_idx  on clinic.visits (patient_id, created_at desc);
create index if not exists visits_doctor_idx   on clinic.visits (doctor_id, created_at desc);
create index if not exists visits_queue_idx    on clinic.visits (status, scheduled_at);

drop trigger if exists visits_touch on clinic.visits;
create trigger visits_touch before update on clinic.visits
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------- encounters ----

-- الكشف. The clinical record, and the table reception has no policy on at all.
--
-- Kept SEPARATE from visits rather than as more columns on it, and that split
-- is the whole privacy design: reception needs the appointment, the queue and
-- the money, and must not need a diagnosis to do any of it. Two tables let RLS
-- express that with a policy each. One table would leave it to the application
-- to remember, forever.
create table if not exists clinic.encounters (
  -- Generated on the device so the doctor can start writing with no network.
  id          uuid primary key,
  patient_id  uuid not null references clinic.patients(id) on delete cascade,
  -- Nullable: a walk-in the doctor sees without reception ever booking a visit
  -- is still a real encounter. P2's queue fills this in.
  visit_id    uuid references clinic.visits(id) on delete set null,

  -- WHO EXAMINED. Never taken from the client — every write path sets this
  -- from auth.uid(), and 20260812100001_clinic_rls.sql revokes UPDATE on the
  -- column so it cannot be moved afterwards.
  doctor_id   uuid not null references clinic.staff(id),

  -- العلامات الحيوية
  temp_c      numeric(4,1)  check (temp_c between 30 and 45),
  pulse       int           check (pulse between 20 and 300),
  bp_sys      int           check (bp_sys between 40 and 300),
  bp_dia      int           check (bp_dia between 20 and 200),
  weight_kg   numeric(5,1)  check (weight_kg between 0 and 400),
  height_cm   numeric(5,1)  check (height_cm between 0 and 260),

  complaint_ar text,
  history_ar   text,
  exam_ar      text,
  diagnosis_ar text,
  plan_ar      text,
  next_visit_on date,

  status      clinic.record_status not null default 'draft',
  signed_at   timestamptz,

  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists encounters_patient_idx on clinic.encounters (patient_id, created_at desc);
create index if not exists encounters_doctor_idx  on clinic.encounters (doctor_id, created_at desc);

drop trigger if exists encounters_touch on clinic.encounters;
create trigger encounters_touch before update on clinic.encounters
  for each row execute function public.touch_updated_at();

-- ------------------------------------------------------- prescriptions ----

create table if not exists clinic.prescriptions (
  -- The device generates this before the row has ever seen a server. It is
  -- also the idempotency key: clinic.sync_prescription() upserts on it, so a
  -- retry after a flaky reconnect produces one prescription and not two.
  id            uuid primary key,
  patient_id    uuid not null references clinic.patients(id) on delete cascade,
  encounter_id  uuid references clinic.encounters(id) on delete set null,
  doctor_id     uuid not null references clinic.staff(id),

  -- Built on the device: '{rx_prefix}-{yyyymmdd}-{counter}'. Unique across the
  -- clinic because the prefix is unique per doctor. Deliberately NOT a
  -- sequence — a sequence needs the server, and the whole point is that the
  -- prescription prints when the server is unreachable.
  rx_no         text not null unique,

  status        clinic.record_status not null default 'draft',
  issued_at     timestamptz,
  printed_count int not null default 0 check (printed_count >= 0),

  -- A correction is a NEW prescription pointing back at the one it replaces.
  -- The original stays in the file, because that is what a medical record is.
  amended_from  uuid references clinic.prescriptions(id) on delete set null,
  amend_reason  text,

  -- When it was written on the device, versus when the server first saw it.
  -- The gap is how long the clinic was offline, and it is worth being able to
  -- ask.
  written_at    timestamptz not null default now(),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists rx_patient_idx  on clinic.prescriptions (patient_id, written_at desc);
create index if not exists rx_doctor_idx    on clinic.prescriptions (doctor_id, written_at desc);
create index if not exists rx_amended_idx   on clinic.prescriptions (amended_from);

drop trigger if exists rx_touch on clinic.prescriptions;
create trigger rx_touch before update on clinic.prescriptions
  for each row execute function public.touch_updated_at();

-- The lines. SNAPSHOTS, not joins — renaming or delisting a drug next year is
-- forbidden from rewriting a prescription written this year. Same rule the
-- shop applies to order lines, and for the same reason: the paper in the
-- patient's hand and the row in the database have to say the same thing
-- forever.
create table if not exists clinic.prescription_items (
  rx_id       uuid not null references clinic.prescriptions(id) on delete cascade,
  line_no     int  not null check (line_no > 0),

  drug_id     uuid,          -- provenance only; may be null for a free-typed name
  drug_name   text not null, -- ← the snapshot, and what actually prints
  form_ar     text,          -- أقراص / شراب / أمبول
  strength    text,          -- 500 مجم

  dose_ar     text,          -- قرص
  frequency_ar text,         -- ٣ مرات يوميًا
  duration_ar  text,         -- ٧ أيام
  route_ar     text,         -- بالفم
  notes_ar     text,         -- بعد الأكل

  primary key (rx_id, line_no)
);

-- --------------------------------------------------------------- drugs ----

-- The catalogue. It is downloaded WHOLE onto every clinic device and searched
-- there, which is what makes "type one letter, see the drug" instant and what
-- makes it keep working with the internet off. Keep the row narrow: every
-- column here is multiplied by a few thousand and pushed over a phone
-- connection.
create table if not exists clinic.drugs (
  id         uuid primary key default gen_random_uuid(),
  trade_name text not null,

  -- The brand as an ARABIC-TYPING DOCTOR SPELLS IT. "كونكور" for Concor,
  -- "فلاجيل" for Flagyl.
  --
  -- Not decoration and not a translation: Egyptian doctors prescribe by brand,
  -- and half of them type Arabic. Without this column the search box answers
  -- "كونكور" with nothing at all while holding the drug, which is the single
  -- most likely way for this feature to feel broken on day one. Caught by an
  -- assertion in tools/schema-check/clinic.mjs, not by inspection.
  trade_name_ar text not null default '',

  generic_ar text,
  generic_en text,
  -- NOT NULL with an empty default, and that is load-bearing rather than
  -- fussy: NULLs are distinct from each other in a UNIQUE constraint, so
  -- (Panadol, null, null) could be inserted a hundred times and the constraint
  -- at the bottom of this table would never once complain.
  form_ar    text not null default '',
  strength   text not null default '',

  -- Folded by the same rule as web/lib/arabic.js, so the device's in-memory
  -- search and any server-side query give the same answer.
  name_key   text generated always as (
    public.fold_arabic(trade_name) || ' ' || public.fold_arabic(trade_name_ar)
    || ' ' || public.fold_arabic(coalesce(generic_ar,''))
    || ' ' || lower(coalesce(generic_en,''))
  ) stored,

  is_active  boolean not null default true,
  -- The delta cursor. clinic.drug_catalog(since) returns rows newer than this.
  updated_at timestamptz not null default now(),

  unique (trade_name, strength, form_ar)
);

create index if not exists drugs_name_key_idx on clinic.drugs (name_key text_pattern_ops);
create index if not exists drugs_updated_idx  on clinic.drugs (updated_at);

drop trigger if exists drugs_touch on clinic.drugs;
create trigger drugs_touch before update on clinic.drugs
  for each row execute function public.touch_updated_at();

-- How often THIS doctor reaches for THIS drug. Sorts their own habits to the
-- top of the picker, which is most of what makes the box feel fast after a
-- week of use.
create table if not exists clinic.drug_usage (
  doctor_id uuid not null references clinic.staff(id) on delete cascade,
  drug_id   uuid not null references clinic.drugs(id) on delete cascade,
  uses      int  not null default 0,
  last_used timestamptz not null default now(),
  primary key (doctor_id, drug_id)
);

-- ---------------------------------------------------------- بروتوكولات ----

-- The same four drugs for the same presentation, every day. One click instead
-- of four lines.
create table if not exists clinic.rx_templates (
  id         uuid primary key default gen_random_uuid(),
  -- NULL = shared with the whole clinic. Otherwise it is this doctor's own.
  doctor_id  uuid references clinic.staff(id) on delete cascade,
  name_ar    text not null,
  notes_ar   text,
  created_at timestamptz not null default now()
);

create table if not exists clinic.rx_template_items (
  template_id  uuid not null references clinic.rx_templates(id) on delete cascade,
  line_no      int  not null check (line_no > 0),
  drug_id      uuid references clinic.drugs(id) on delete set null,
  drug_name    text not null,
  form_ar      text,
  strength     text,
  dose_ar      text,
  frequency_ar text,
  duration_ar  text,
  route_ar     text,
  notes_ar     text,
  primary key (template_id, line_no)
);

-- ------------------------------------------------ تحاليل وأشعة (P4) ----

create table if not exists clinic.lab_tests (
  id        uuid primary key default gen_random_uuid(),
  name_ar   text not null,
  name_en   text,
  -- Same NOT NULL DEFAULT reasoning as clinic.drugs.form_ar: a nullable column
  -- inside a UNIQUE constraint does not deduplicate anything.
  category  text not null default 'تحاليل',   -- تحاليل / أشعة / وظائف
  name_key  text generated always as (public.fold_arabic(name_ar)) stored,
  is_active boolean not null default true,
  updated_at timestamptz not null default now(),
  unique (name_ar, category)
);

create table if not exists clinic.lab_requests (
  id           uuid primary key,
  patient_id   uuid not null references clinic.patients(id) on delete cascade,
  encounter_id uuid references clinic.encounters(id) on delete set null,
  doctor_id    uuid not null references clinic.staff(id),
  req_no       text not null unique,
  notes_ar     text,
  written_at   timestamptz not null default now(),
  created_at   timestamptz not null default now()
);

create table if not exists clinic.lab_request_items (
  req_id   uuid not null references clinic.lab_requests(id) on delete cascade,
  line_no  int  not null check (line_no > 0),
  test_id  uuid,
  test_name text not null,   -- snapshot, same rule as prescription_items
  notes_ar text,
  primary key (req_id, line_no)
);

-- Results the patient brings back, photographed. The bucket is private and
-- stays private — same shape as public.customer_uploads.
create table if not exists clinic.attachments (
  id           uuid primary key default gen_random_uuid(),
  patient_id   uuid not null references clinic.patients(id) on delete cascade,
  encounter_id uuid references clinic.encounters(id) on delete set null,
  storage_path text not null unique,
  original_name text,
  kind         text,     -- تحليل / أشعة / تقرير
  bytes        bigint,
  uploaded_by  uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now()
);

-- ------------------------------------------------------------ الفلوس ----

create table if not exists clinic.payments (
  id          uuid primary key default gen_random_uuid(),
  visit_id    uuid not null references clinic.visits(id) on delete cascade,
  amount      numeric(10,2) not null check (amount > 0),
  method      clinic.pay_method not null default 'cash',
  received_by uuid references public.profiles(id) on delete set null,
  note_ar     text,
  created_at  timestamptz not null default now()
);

create index if not exists payments_visit_idx on clinic.payments (visit_id);
create index if not exists payments_day_idx   on clinic.payments (created_at);

-- ------------------------------------------------------------- الأثر ----

-- Who did what, and WHO LOOKED. A clinic where several doctors can open the
-- same file needs the second half of that sentence as much as the first — it
-- is the only thing that makes shared access reviewable rather than merely
-- convenient.
--
-- Append-only: 20260812100001_clinic_rls.sql grants INSERT and SELECT and
-- nothing else, to anyone, including the director.
create table if not exists clinic.audit_events (
  id         bigserial primary key,
  actor_id   uuid references public.profiles(id) on delete set null,
  action     text not null,        -- viewed_patient / issued_rx / amended_rx …
  entity     text not null,        -- patients / prescriptions …
  entity_id  uuid,
  detail     jsonb,
  created_at timestamptz not null default now()
);

create index if not exists audit_actor_idx  on clinic.audit_events (actor_id, created_at desc);
create index if not exists audit_entity_idx on clinic.audit_events (entity, entity_id);

-- ## 20260812100001_clinic_rls.sql
-- ============================================================================
--  العيادة — الصلاحيات
--
--  ⚠  Sorts AFTER 20260810100006_rls.sql, so nothing here is undone by it.
--
--  THE RULE FOR THIS WHOLE SCHEMA, AND IT HAS NO EXCEPTIONS:
--  `anon` gets nothing. Not a table, not a column, not a function. The shop has
--  a deliberate anonymous read surface because a shop window nobody can look
--  into is pointless; a patient file has no equivalent argument. anon does not
--  even hold USAGE on the schema (20260812100000_clinic_schema.sql:32), so
--  every grant below is a second lock on a door that has no handle.
--
--  Supabase sets `alter default privileges` for schema public only. A new
--  schema starts with no grants at all, which is exactly what we want: every
--  privilege below had to be typed out on purpose.
--
--  WHO SEES WHAT
--
--    reception  الاستقبال — patients, visits, queue, money. NEVER a diagnosis.
--    doctor     الدكتور    — everything clinical, for every patient in the
--                            clinic (one shared file), but WRITES only under
--                            their own name.
--    director   الديريكتور — a doctor, plus reports, staff and settings.
-- ============================================================================

alter table clinic.staff              enable row level security;
alter table clinic.settings           enable row level security;
alter table clinic.patients           enable row level security;
alter table clinic.visits             enable row level security;
alter table clinic.encounters         enable row level security;
alter table clinic.prescriptions      enable row level security;
alter table clinic.prescription_items enable row level security;
alter table clinic.drugs              enable row level security;
alter table clinic.drug_usage         enable row level security;
alter table clinic.rx_templates       enable row level security;
alter table clinic.rx_template_items  enable row level security;
alter table clinic.lab_tests          enable row level security;
alter table clinic.lab_requests       enable row level security;
alter table clinic.lab_request_items  enable row level security;
alter table clinic.attachments        enable row level security;
alter table clinic.payments           enable row level security;
alter table clinic.audit_events       enable row level security;

-- Belt and braces. anon has no USAGE on the schema, so it cannot reach these
-- names at all — but a future migration that grants USAGE by accident should
-- still find every table bare underneath.
revoke all on all tables    in schema clinic from anon, public;
revoke all on all functions in schema clinic from anon, public;
revoke all on all sequences in schema clinic from anon, public;

-- ---------------------------------------------------------------- staff ----

-- Every member of staff can read the staff list. Not a privacy hole — it is
-- how "كتبها: د. أحمد" appears under a prescription line, and how the queue
-- names the doctor a patient is waiting for.
drop policy if exists staff_read on clinic.staff;
create policy staff_read on clinic.staff
  for select to authenticated
  using (clinic.is_staff());

drop policy if exists staff_write on clinic.staff;
create policy staff_write on clinic.staff
  for all to authenticated
  using (clinic.is_director()) with check (clinic.is_director());

-- A doctor may fix how their own name and title PRINT without being able to
-- promote themselves. Same shape as the profiles.role lock in
-- 20260810100006_rls.sql:98: the privilege is taken at the column level, so
-- the rule cannot be argued around by a policy that reads "the row is mine".
revoke update on clinic.staff from authenticated;
grant  update (display_name, title_ar, specialty_ar, syndicate_no, signature_url)
  on clinic.staff to authenticated;

drop policy if exists staff_self_update on clinic.staff;
create policy staff_self_update on clinic.staff
  for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

grant select, insert, delete on clinic.staff to authenticated;

-- ------------------------------------------------------------- settings ----

drop policy if exists settings_read on clinic.settings;
create policy settings_read on clinic.settings
  for select to authenticated
  using (clinic.is_staff());

-- The print offsets are read by every prescription and changed by one person.
drop policy if exists settings_write on clinic.settings;
create policy settings_write on clinic.settings
  for all to authenticated
  using (clinic.is_director()) with check (clinic.is_director());

grant select, insert, update, delete on clinic.settings to authenticated;

-- ------------------------------------------------------------ patients ----

-- Reception registers patients and looks them up; that is the job. What they
-- cannot reach is clinic.encounters and clinic.prescriptions, below.
drop policy if exists patients_read on clinic.patients;
create policy patients_read on clinic.patients
  for select to authenticated
  using (clinic.is_staff());

drop policy if exists patients_write on clinic.patients;
create policy patients_write on clinic.patients
  for all to authenticated
  using (clinic.is_staff()) with check (clinic.is_staff());

-- The file number is assigned by clinic.sync_patient() and by nobody else. A
-- device that could set it would hand two patients the same number the first
-- time two devices registered someone while offline.
revoke update on clinic.patients from authenticated;
grant  update (full_name, phone, gender, birth_date, address_ar,
               allergies_ar, chronic_ar, notes_ar)
  on clinic.patients to authenticated;

grant select, insert, delete on clinic.patients to authenticated;

-- -------------------------------------------------------------- visits ----

drop policy if exists visits_read on clinic.visits;
create policy visits_read on clinic.visits
  for select to authenticated
  using (clinic.is_staff());

drop policy if exists visits_write on clinic.visits;
create policy visits_write on clinic.visits
  for all to authenticated
  using (clinic.is_staff()) with check (clinic.is_staff());

grant select, insert, update, delete on clinic.visits to authenticated;

-- ---------------------------------------------------------- encounters ----
--
--  READ is clinic-wide: any doctor opening a patient sees the whole file,
--  including what a colleague wrote. That is a deliberate CLINICAL decision,
--  not an oversight — a doctor who cannot see what the patient is already
--  taking is a doctor prescribing blind, and in a clinic where two doctors
--  share the same patients that is the likelier harm by far.
--
--  WRITE is yours alone. You author under your own name, you may correct your
--  own draft, and you may not touch a colleague's record. A disagreement is a
--  new encounter in your name, not an edit to theirs.

drop policy if exists encounters_read on clinic.encounters;
create policy encounters_read on clinic.encounters
  for select to authenticated
  using (clinic.is_clinician());

drop policy if exists encounters_insert on clinic.encounters;
create policy encounters_insert on clinic.encounters
  for insert to authenticated
  with check (clinic.is_clinician() and doctor_id = auth.uid());

drop policy if exists encounters_update on clinic.encounters;
create policy encounters_update on clinic.encounters
  for update to authenticated
  using (clinic.is_clinician() and doctor_id = auth.uid() and status = 'draft')
  with check (doctor_id = auth.uid());

-- No delete policy, on purpose. A clinical note is not deleted; a draft that
-- was never signed simply stays a draft.

-- Authorship and signature are set by the RPCs and are unreachable from the
-- client. Note the table-level revoke first: revoking a single column while a
-- table-level UPDATE grant stands would change nothing at all.
revoke update on clinic.encounters from authenticated;
grant  update (temp_c, pulse, bp_sys, bp_dia, weight_kg, height_cm,
               complaint_ar, history_ar, exam_ar, diagnosis_ar, plan_ar,
               next_visit_on, visit_id)
  on clinic.encounters to authenticated;

grant select, insert on clinic.encounters to authenticated;

-- ------------------------------------------------------- prescriptions ----

drop policy if exists rx_read on clinic.prescriptions;
create policy rx_read on clinic.prescriptions
  for select to authenticated
  using (clinic.is_clinician());

drop policy if exists rx_insert on clinic.prescriptions;
create policy rx_insert on clinic.prescriptions
  for insert to authenticated
  with check (clinic.is_clinician() and doctor_id = auth.uid());

drop policy if exists rx_update on clinic.prescriptions;
create policy rx_update on clinic.prescriptions
  for update to authenticated
  using (clinic.is_clinician() and doctor_id = auth.uid() and status = 'draft')
  with check (doctor_id = auth.uid());

-- status, rx_no, doctor_id and amended_from are all off the table. They move
-- only through clinic.issue_prescription() and clinic.amend_prescription(),
-- which are SECURITY DEFINER and therefore reach past this revoke. A rule you
-- can go around is a suggestion — the same sentence as
-- 20260810100009_orders.sql:298.
revoke update on clinic.prescriptions from authenticated;
grant  update (encounter_id) on clinic.prescriptions to authenticated;

grant select, insert on clinic.prescriptions to authenticated;

-- The lines follow their prescription: visible if it is, editable while it is
-- still your draft.
drop policy if exists rx_items_read on clinic.prescription_items;
create policy rx_items_read on clinic.prescription_items
  for select to authenticated
  using (clinic.is_clinician());

drop policy if exists rx_items_write on clinic.prescription_items;
create policy rx_items_write on clinic.prescription_items
  for all to authenticated
  using (exists (select 1 from clinic.prescriptions p
                  where p.id = rx_id and p.doctor_id = auth.uid()
                    and p.status = 'draft'))
  with check (exists (select 1 from clinic.prescriptions p
                       where p.id = rx_id and p.doctor_id = auth.uid()
                         and p.status = 'draft'));

grant select, insert, update, delete on clinic.prescription_items to authenticated;

-- --------------------------------------------------- كتالوج الأدوية ----

-- Read by every clinician, on every device, in full. Written by the director.
drop policy if exists drugs_read on clinic.drugs;
create policy drugs_read on clinic.drugs
  for select to authenticated
  using (clinic.is_staff());

drop policy if exists drugs_write on clinic.drugs;
create policy drugs_write on clinic.drugs
  for all to authenticated
  using (clinic.is_director()) with check (clinic.is_director());

grant select, insert, update, delete on clinic.drugs to authenticated;

drop policy if exists lab_tests_read on clinic.lab_tests;
create policy lab_tests_read on clinic.lab_tests
  for select to authenticated
  using (clinic.is_staff());

drop policy if exists lab_tests_write on clinic.lab_tests;
create policy lab_tests_write on clinic.lab_tests
  for all to authenticated
  using (clinic.is_director()) with check (clinic.is_director());

grant select, insert, update, delete on clinic.lab_tests to authenticated;

-- Your own habits, nobody else's. Reading another doctor's prescribing
-- frequency is not needed to sort your own picker.
drop policy if exists drug_usage_own on clinic.drug_usage;
create policy drug_usage_own on clinic.drug_usage
  for all to authenticated
  using (doctor_id = auth.uid()) with check (doctor_id = auth.uid());

grant select, insert, update, delete on clinic.drug_usage to authenticated;

-- ------------------------------------------------------- بروتوكولات ----

-- Yours, or the clinic's shared ones (doctor_id is null).
drop policy if exists rx_templates_read on clinic.rx_templates;
create policy rx_templates_read on clinic.rx_templates
  for select to authenticated
  using (clinic.is_clinician() and (doctor_id is null or doctor_id = auth.uid()));

drop policy if exists rx_templates_write on clinic.rx_templates;
create policy rx_templates_write on clinic.rx_templates
  for all to authenticated
  using (doctor_id = auth.uid() or (doctor_id is null and clinic.is_director()))
  with check (doctor_id = auth.uid() or (doctor_id is null and clinic.is_director()));

grant select, insert, update, delete on clinic.rx_templates to authenticated;

drop policy if exists rx_template_items_all on clinic.rx_template_items;
create policy rx_template_items_all on clinic.rx_template_items
  for all to authenticated
  using (exists (select 1 from clinic.rx_templates t
                  where t.id = template_id
                    and (t.doctor_id = auth.uid()
                         or (t.doctor_id is null and clinic.is_clinician()))))
  with check (exists (select 1 from clinic.rx_templates t
                       where t.id = template_id
                         and (t.doctor_id = auth.uid()
                              or (t.doctor_id is null and clinic.is_director()))));

grant select, insert, update, delete on clinic.rx_template_items to authenticated;

-- --------------------------------------------------- تحاليل ومرفقات ----

drop policy if exists lab_req_read on clinic.lab_requests;
create policy lab_req_read on clinic.lab_requests
  for select to authenticated
  using (clinic.is_clinician());

drop policy if exists lab_req_write on clinic.lab_requests;
create policy lab_req_write on clinic.lab_requests
  for all to authenticated
  using (clinic.is_clinician() and doctor_id = auth.uid())
  with check (clinic.is_clinician() and doctor_id = auth.uid());

grant select, insert, update, delete on clinic.lab_requests to authenticated;

drop policy if exists lab_req_items_all on clinic.lab_request_items;
create policy lab_req_items_all on clinic.lab_request_items
  for all to authenticated
  using (clinic.is_clinician())
  with check (exists (select 1 from clinic.lab_requests r
                       where r.id = req_id and r.doctor_id = auth.uid()));

grant select, insert, update, delete on clinic.lab_request_items to authenticated;

-- A scanned result is a clinical document. Reception hands the paper over; it
-- does not read it.
drop policy if exists attachments_read on clinic.attachments;
create policy attachments_read on clinic.attachments
  for select to authenticated
  using (clinic.is_clinician());

drop policy if exists attachments_write on clinic.attachments;
create policy attachments_write on clinic.attachments
  for all to authenticated
  using (clinic.is_clinician()) with check (clinic.is_clinician());

grant select, insert, update, delete on clinic.attachments to authenticated;

-- ------------------------------------------------------------- الفلوس ----
--
--  Reception takes the money and must see the day's takings to balance the
--  drawer. A doctor sees what was collected against their OWN visits — enough
--  to check their day, not enough to audit a colleague's. The director sees
--  everything, which is the whole point of the role.

drop policy if exists payments_read on clinic.payments;
create policy payments_read on clinic.payments
  for select to authenticated
  using (
    clinic.is_reception()
    or clinic.is_director()
    or exists (select 1 from clinic.visits v
                where v.id = visit_id and v.doctor_id = auth.uid())
  );

drop policy if exists payments_write on clinic.payments;
create policy payments_write on clinic.payments
  for all to authenticated
  using (clinic.is_reception() or clinic.is_director())
  with check (clinic.is_reception() or clinic.is_director());

grant select, insert, update, delete on clinic.payments to authenticated;

-- -------------------------------------------------------------- الأثر ----
--
--  APPEND-ONLY, for everyone. There is no UPDATE policy and no DELETE policy
--  on this table and there must never be one — including for the director. An
--  audit log the audited party can edit is decoration.

drop policy if exists audit_insert on clinic.audit_events;
create policy audit_insert on clinic.audit_events
  for insert to authenticated
  with check (clinic.is_staff() and actor_id = auth.uid());

drop policy if exists audit_read on clinic.audit_events;
create policy audit_read on clinic.audit_events
  for select to authenticated
  using (clinic.is_director());

grant select, insert on clinic.audit_events to authenticated;
grant usage on sequence clinic.audit_events_id_seq to authenticated;

-- ---------------------------------------------------------------------------
--  The predicates themselves. Executable by a signed-in session, because every
--  policy above calls them; never by anon.
-- ---------------------------------------------------------------------------
revoke execute on function clinic.my_role()      from public, anon;
revoke execute on function clinic.is_doctor()    from public, anon;
revoke execute on function clinic.is_director()  from public, anon;
revoke execute on function clinic.is_reception() from public, anon;
revoke execute on function clinic.is_clinician() from public, anon;
revoke execute on function clinic.is_staff()     from public, anon;

grant execute on function clinic.my_role()      to authenticated;
grant execute on function clinic.is_doctor()    to authenticated;
grant execute on function clinic.is_director()  to authenticated;
grant execute on function clinic.is_reception() to authenticated;
grant execute on function clinic.is_clinician() to authenticated;
grant execute on function clinic.is_staff()     to authenticated;

-- ## 20260812100002_clinic_rx.sql
-- ============================================================================
--  العيادة — الروشتة
--
--  ⚠  Sorts AFTER 20260810100006_rls.sql. Carries its own grants, at the
--     bottom.
--
--  Two problems are solved here and they pull in opposite directions.
--
--  1. A PRESCRIPTION MUST BE WRITABLE AND PRINTABLE WITH NO NETWORK. The
--     clinic's internet drops mid-session and the patient is standing there.
--     So the device generates the id, generates the number, writes to its own
--     IndexedDB, and prints from there. The server sees it later.
--
--  2. A PRESCRIPTION IS A MEDICAL RECORD. Once issued it does not change. A
--     correction is a NEW prescription that points back at the old one, and
--     both stay in the file.
--
--  The reconciliation is clinic.sync_prescription(): IDEMPOTENT on the id the
--  device generated. A reconnect that retries a request whose response was
--  lost produces one prescription, not two. That single property is what makes
--  offline writing safe here, and it is why prescriptions are append-only and
--  authored by exactly one device — the moment two devices could edit one row,
--  none of this would hold.
-- ============================================================================

-- ---------------------------------------------------------------------------
--  القفل — الروشتة اللي اتطبعت مش بتتعدّل
--
--  20260812100001_clinic_rls.sql already revoked UPDATE on every column that
--  matters, so a client cannot reach these. This trigger is the second lock:
--  it also binds the SECURITY DEFINER functions below, which run as the owner
--  and sail straight past a grant.
-- ---------------------------------------------------------------------------
create or replace function clinic.freeze_issued_rx()
returns trigger
language plpgsql set search_path = clinic, public as $$
begin
  if old.status = 'issued' then
    -- Cancelling an issued prescription is legitimate — the patient never
    -- collected it, the drug was out of stock. Everything else is not.
    if new.status is distinct from old.status and new.status <> 'cancelled' then
      raise exception 'RX_ISSUED' using errcode = 'P0001';
    end if;

    if new.rx_no      is distinct from old.rx_no
    or new.patient_id is distinct from old.patient_id
    or new.doctor_id  is distinct from old.doctor_id
    or new.encounter_id is distinct from old.encounter_id
    or new.written_at is distinct from old.written_at
    or new.issued_at  is distinct from old.issued_at
    or new.amended_from is distinct from old.amended_from
    then
      raise exception 'RX_ISSUED' using errcode = 'P0001';
    end if;
    -- printed_count and updated_at are free to move. Printing a second copy
    -- is not an amendment.
  end if;
  return new;
end $$;

drop trigger if exists rx_freeze on clinic.prescriptions;
create trigger rx_freeze before update on clinic.prescriptions
  for each row execute function clinic.freeze_issued_rx();

-- The lines are frozen with the prescription. The RLS policy on
-- prescription_items already requires the parent to be a draft; this catches
-- the definer path too.
--
-- NOTE the TG_OP branch. In a DELETE trigger PL/pgSQL leaves NEW unassigned,
-- and `coalesce(new.rx_id, old.rx_id)` does not evaluate to OLD — it raises
-- "record new is not assigned yet" and takes the delete down with it.
create or replace function clinic.freeze_issued_rx_items()
returns trigger
language plpgsql set search_path = clinic, public as $$
declare
  v_rx     uuid;
  v_status clinic.record_status;
begin
  v_rx := case when tg_op = 'DELETE' then old.rx_id else new.rx_id end;

  select status into v_status from clinic.prescriptions where id = v_rx;
  if v_status = 'issued' then
    raise exception 'RX_ISSUED' using errcode = 'P0001';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end $$;

drop trigger if exists rx_items_freeze on clinic.prescription_items;
create trigger rx_items_freeze before insert or update or delete
  on clinic.prescription_items
  for each row execute function clinic.freeze_issued_rx_items();

-- ---------------------------------------------------------------------------
--  الكشف — رفع من الجهاز
--
--  Same shape as the prescription: the device owns the id, the server decides
--  authorship. An encounter is editable while it is a draft and frozen once
--  signed, which is what `signed` means.
-- ---------------------------------------------------------------------------
create or replace function clinic.sync_encounter(p_payload jsonb)
returns uuid
language plpgsql security definer set search_path = clinic, public as $$
declare
  v_id      uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_patient uuid := nullif(p_payload ->> 'patient_id', '')::uuid;
  v_owner   uuid;
  v_status  clinic.record_status;
begin
  if not clinic.is_clinician() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if v_id is null or v_patient is null then
    raise exception 'BAD_PAYLOAD' using errcode = 'P0001';
  end if;
  if not exists (select 1 from clinic.patients where id = v_patient) then
    raise exception 'NO_PATIENT' using errcode = 'P0001';
  end if;

  select doctor_id, status into v_owner, v_status
    from clinic.encounters where id = v_id;

  if v_owner is not null then
    if v_owner <> auth.uid() then
      raise exception 'NOT_YOURS' using errcode = 'P0001';
    end if;
    -- The retry case. A signed encounter that arrives again is the same
    -- encounter; say yes and change nothing.
    if v_status = 'issued' then
      return v_id;
    end if;
  end if;

  insert into clinic.encounters as e (
    id, patient_id, visit_id, doctor_id,
    temp_c, pulse, bp_sys, bp_dia, weight_kg, height_cm,
    complaint_ar, history_ar, exam_ar, diagnosis_ar, plan_ar, next_visit_on,
    status, signed_at
  ) values (
    v_id, v_patient,
    nullif(p_payload ->> 'visit_id', '')::uuid,
    auth.uid(),                                  -- ← never from the payload
    nullif(p_payload ->> 'temp_c','')::numeric,
    nullif(p_payload ->> 'pulse','')::int,
    nullif(p_payload ->> 'bp_sys','')::int,
    nullif(p_payload ->> 'bp_dia','')::int,
    nullif(p_payload ->> 'weight_kg','')::numeric,
    nullif(p_payload ->> 'height_cm','')::numeric,
    nullif(p_payload ->> 'complaint_ar',''),
    nullif(p_payload ->> 'history_ar',''),
    nullif(p_payload ->> 'exam_ar',''),
    nullif(p_payload ->> 'diagnosis_ar',''),
    nullif(p_payload ->> 'plan_ar',''),
    nullif(p_payload ->> 'next_visit_on','')::date,
    coalesce(nullif(p_payload ->> 'status','')::clinic.record_status, 'draft'),
    case when p_payload ->> 'status' = 'issued' then now() end
  )
  on conflict (id) do update set
    visit_id      = excluded.visit_id,
    temp_c        = excluded.temp_c,
    pulse         = excluded.pulse,
    bp_sys        = excluded.bp_sys,
    bp_dia        = excluded.bp_dia,
    weight_kg     = excluded.weight_kg,
    height_cm     = excluded.height_cm,
    complaint_ar  = excluded.complaint_ar,
    history_ar    = excluded.history_ar,
    exam_ar       = excluded.exam_ar,
    diagnosis_ar  = excluded.diagnosis_ar,
    plan_ar       = excluded.plan_ar,
    next_visit_on = excluded.next_visit_on,
    status        = excluded.status,
    signed_at     = coalesce(e.signed_at, excluded.signed_at);

  return v_id;
end $$;

-- ---------------------------------------------------------------------------
--  الروشتة — رفع من الجهاز، والرفع مرتين = روشتة واحدة
-- ---------------------------------------------------------------------------
create or replace function clinic.sync_prescription(p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = clinic, public as $$
declare
  v_id       uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_patient  uuid := nullif(p_payload ->> 'patient_id', '')::uuid;
  v_rx_no    text := nullif(trim(p_payload ->> 'rx_no'), '');
  v_status   clinic.record_status :=
               coalesce(nullif(p_payload ->> 'status','')::clinic.record_status, 'draft');
  v_prefix   text;
  v_owner    uuid;
  v_existing clinic.record_status;
  v_item     jsonb;
  v_lines    int := 0;
begin
  if not clinic.is_clinician() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if v_id is null or v_patient is null or v_rx_no is null then
    raise exception 'BAD_PAYLOAD' using errcode = 'P0001';
  end if;
  if not exists (select 1 from clinic.patients where id = v_patient) then
    raise exception 'NO_PATIENT' using errcode = 'P0001';
  end if;

  -- The number was built on the device from this doctor's own prefix. Checking
  -- it here is what stops one doctor's device — through a bug or otherwise —
  -- from filing prescriptions inside a colleague's numbering, which would make
  -- the director's report quietly wrong rather than loudly broken.
  select rx_prefix into v_prefix from clinic.staff where id = auth.uid();
  if v_prefix is null or v_rx_no not like v_prefix || '-%' then
    raise exception 'RX_PREFIX_MISMATCH' using errcode = 'P0001';
  end if;

  select doctor_id, status into v_owner, v_existing
    from clinic.prescriptions where id = v_id;

  if v_owner is not null then
    if v_owner <> auth.uid() then
      raise exception 'NOT_YOUR_RX' using errcode = 'P0001';
    end if;
    -- ⚠ THE IDEMPOTENCY CASE, and the reason this function exists.
    -- The device sent this, the reply was lost to a dying connection, and the
    -- outbox is retrying. The prescription is already here and already issued;
    -- return it and touch nothing. Inserting again would put a second copy of
    -- the same paper in the patient's file.
    if v_existing = 'issued' then
      return jsonb_build_object('id', v_id, 'rx_no', v_rx_no,
                                'status', 'issued', 'duplicate', true);
    end if;
  end if;

  insert into clinic.prescriptions as r (
    id, patient_id, encounter_id, doctor_id, rx_no, status, issued_at, written_at
  ) values (
    v_id, v_patient,
    nullif(p_payload ->> 'encounter_id', '')::uuid,
    auth.uid(),                                  -- ← never from the payload
    v_rx_no, 'draft', null,
    coalesce(nullif(p_payload ->> 'written_at','')::timestamptz, now())
  )
  on conflict (id) do update set
    encounter_id = excluded.encounter_id,
    patient_id   = excluded.patient_id;

  -- Lines are replaced wholesale while the prescription is a draft. Merging
  -- them would need a stable line identity the device has no reason to keep.
  delete from clinic.prescription_items where rx_id = v_id;

  for v_item in select * from jsonb_array_elements(coalesce(p_payload -> 'items', '[]'::jsonb))
  loop
    if nullif(trim(v_item ->> 'drug_name'), '') is null then
      raise exception 'RX_LINE_EMPTY' using errcode = 'P0001';
    end if;
    v_lines := v_lines + 1;

    insert into clinic.prescription_items (
      rx_id, line_no, drug_id, drug_name, form_ar, strength,
      dose_ar, frequency_ar, duration_ar, route_ar, notes_ar
    ) values (
      v_id, v_lines,
      nullif(v_item ->> 'drug_id','')::uuid,
      trim(v_item ->> 'drug_name'),
      nullif(v_item ->> 'form_ar',''),
      nullif(v_item ->> 'strength',''),
      nullif(v_item ->> 'dose_ar',''),
      nullif(v_item ->> 'frequency_ar',''),
      nullif(v_item ->> 'duration_ar',''),
      nullif(v_item ->> 'route_ar',''),
      nullif(v_item ->> 'notes_ar','')
    );

    -- This doctor's habits, for their own picker.
    if nullif(v_item ->> 'drug_id','') is not null then
      insert into clinic.drug_usage (doctor_id, drug_id, uses, last_used)
      values (auth.uid(), (v_item ->> 'drug_id')::uuid, 1, now())
      on conflict (doctor_id, drug_id) do update
        set uses = clinic.drug_usage.uses + 1, last_used = now();
    end if;
  end loop;

  if v_status = 'issued' then
    if v_lines = 0 then
      raise exception 'RX_EMPTY' using errcode = 'P0001';
    end if;
    update clinic.prescriptions
       set status = 'issued', issued_at = coalesce(issued_at, now())
     where id = v_id;

    insert into clinic.audit_events (actor_id, action, entity, entity_id, detail)
    values (auth.uid(), 'issued_rx', 'prescriptions', v_id,
            jsonb_build_object('rx_no', v_rx_no, 'lines', v_lines,
                               'offline_for_seconds',
                               extract(epoch from now() -
                                 coalesce(nullif(p_payload ->> 'written_at','')::timestamptz, now()))::bigint));
  end if;

  return jsonb_build_object('id', v_id, 'rx_no', v_rx_no,
                            'status', v_status, 'duplicate', false);
end $$;

-- ---------------------------------------------------------------------------
--  إصدار روشتة كانت مسوّدة
-- ---------------------------------------------------------------------------
create or replace function clinic.issue_prescription(p_id uuid)
returns void
language plpgsql security definer set search_path = clinic, public as $$
declare v_owner uuid; v_status clinic.record_status; v_lines int;
begin
  select doctor_id, status into v_owner, v_status
    from clinic.prescriptions where id = p_id;

  if v_owner is null then
    raise exception 'NO_RX' using errcode = 'P0001';
  end if;
  if v_owner <> auth.uid() then
    raise exception 'NOT_YOUR_RX' using errcode = 'P0001';
  end if;
  if v_status = 'issued' then
    return;                    -- already done; saying so twice is not an error
  end if;

  select count(*) into v_lines from clinic.prescription_items where rx_id = p_id;
  if v_lines = 0 then
    raise exception 'RX_EMPTY' using errcode = 'P0001';
  end if;

  update clinic.prescriptions
     set status = 'issued', issued_at = now()
   where id = p_id;

  insert into clinic.audit_events (actor_id, action, entity, entity_id)
  values (auth.uid(), 'issued_rx', 'prescriptions', p_id);
end $$;

-- ---------------------------------------------------------------------------
--  التعديل — نسخة جديدة، والأصل مايتلمسش
--
--  Any clinician may amend, including a colleague, and this is NOT a hole in
--  the "you cannot edit another doctor's record" rule: the colleague's row is
--  not touched at all. What happens is a new prescription, in the amender's
--  own name, carrying a pointer back. Both papers stay in the file and the
--  audit log says who wrote which — which is exactly what a second doctor
--  correcting a dose should leave behind.
-- ---------------------------------------------------------------------------
create or replace function clinic.amend_prescription(p_id uuid, p_reason text)
returns uuid
language plpgsql security definer set search_path = clinic, public as $$
declare
  v_new    uuid := gen_random_uuid();
  v_prefix text;
  v_seq    bigint;
  v_src    clinic.prescriptions%rowtype;
begin
  if not clinic.is_clinician() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if nullif(trim(coalesce(p_reason,'')), '') is null then
    raise exception 'AMEND_REASON_REQUIRED' using errcode = 'P0001';
  end if;

  select * into v_src from clinic.prescriptions where id = p_id;
  if v_src.id is null then
    raise exception 'NO_RX' using errcode = 'P0001';
  end if;

  select rx_prefix into v_prefix from clinic.staff where id = auth.uid();

  -- This one IS numbered on the server: amending needs the original in front
  -- of you, so it never happens offline, and a server-side counter avoids
  -- colliding with whatever the device's local counter is up to.
  select count(*) + 1 into v_seq
    from clinic.prescriptions
   where doctor_id = auth.uid()
     and written_at::date = current_date;

  insert into clinic.prescriptions (
    id, patient_id, encounter_id, doctor_id, rx_no, status,
    amended_from, amend_reason, written_at
  ) values (
    v_new, v_src.patient_id, v_src.encounter_id, auth.uid(),
    v_prefix || '-' || to_char(current_date, 'YYYYMMDD') || '-ت' || lpad(v_seq::text, 4, '0'),
    'draft', p_id, trim(p_reason), now()
  );

  insert into clinic.prescription_items (
    rx_id, line_no, drug_id, drug_name, form_ar, strength,
    dose_ar, frequency_ar, duration_ar, route_ar, notes_ar
  )
  select v_new, line_no, drug_id, drug_name, form_ar, strength,
         dose_ar, frequency_ar, duration_ar, route_ar, notes_ar
    from clinic.prescription_items where rx_id = p_id;

  insert into clinic.audit_events (actor_id, action, entity, entity_id, detail)
  values (auth.uid(), 'amended_rx', 'prescriptions', v_new,
          jsonb_build_object('amended_from', p_id, 'reason', trim(p_reason)));

  return v_new;
end $$;

-- ---------------------------------------------------------------------------
--  طبعتها — عدّاد، مش تعديل
-- ---------------------------------------------------------------------------
create or replace function clinic.mark_printed(p_id uuid)
returns void
language plpgsql security definer set search_path = clinic, public as $$
begin
  if not clinic.is_clinician() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  update clinic.prescriptions set printed_count = printed_count + 1 where id = p_id;
end $$;

-- ---------------------------------------------------------------------------
--  ملف المريض كامل — زيارات وكشوفات وروشتات، وقدام كل واحدة اسم دكتورها
--
--  ONE call rather than five round trips, because this is what opens when a
--  patient sits down and the clinic's connection is the slow part.
-- ---------------------------------------------------------------------------
create or replace function clinic.patient_file(p_patient uuid)
returns jsonb
language sql stable security definer set search_path = clinic, public as $$
  select case when not clinic.is_clinician() then null else jsonb_build_object(
    'patient', (select to_jsonb(p) from clinic.patients p where p.id = p_patient),
    'encounters', coalesce((
      select jsonb_agg(x order by x ->> 'created_at' desc) from (
        select to_jsonb(e) || jsonb_build_object('doctor_name', s.display_name) as x
          from clinic.encounters e
          join clinic.staff s on s.id = e.doctor_id
         where e.patient_id = p_patient
      ) t), '[]'::jsonb),
    'prescriptions', coalesce((
      select jsonb_agg(x order by x ->> 'written_at' desc) from (
        select to_jsonb(r)
             || jsonb_build_object(
                  'doctor_name', s.display_name,
                  'superseded', exists (select 1 from clinic.prescriptions c
                                         where c.amended_from = r.id),
                  'items', coalesce((
                    select jsonb_agg(to_jsonb(i) order by i.line_no)
                      from clinic.prescription_items i where i.rx_id = r.id), '[]'::jsonb)
                ) as x
          from clinic.prescriptions r
          join clinic.staff s on s.id = r.doctor_id
         where r.patient_id = p_patient
      ) t), '[]'::jsonb)
  ) end
$$;

-- ---------------------------------------------------------------- grants ---

revoke execute on function clinic.sync_encounter(jsonb)          from public, anon;
revoke execute on function clinic.sync_prescription(jsonb)       from public, anon;
revoke execute on function clinic.issue_prescription(uuid)       from public, anon;
revoke execute on function clinic.amend_prescription(uuid, text) from public, anon;
revoke execute on function clinic.mark_printed(uuid)             from public, anon;
revoke execute on function clinic.patient_file(uuid)             from public, anon;
revoke execute on function clinic.freeze_issued_rx()             from public, anon;
revoke execute on function clinic.freeze_issued_rx_items()       from public, anon;

grant execute on function clinic.sync_encounter(jsonb)          to authenticated;
grant execute on function clinic.sync_prescription(jsonb)       to authenticated;
grant execute on function clinic.issue_prescription(uuid)       to authenticated;
grant execute on function clinic.amend_prescription(uuid, text) to authenticated;
grant execute on function clinic.mark_printed(uuid)             to authenticated;
grant execute on function clinic.patient_file(uuid)             to authenticated;

-- ## 20260812100003_clinic_visits.sql
-- ============================================================================
--  العيادة — المرضى والزيارات والطابور
--
--  ⚠  Sorts AFTER 20260810100006_rls.sql. Carries its own grants, at the
--     bottom.
-- ============================================================================

-- ---------------------------------------------------------------------------
--  تسجيل مريض — من الجهاز، وممكن يكون اتسجّل والنت مقطوع
--
--  The device owns the id. The SERVER owns the file number, and that split is
--  deliberate: two receptionists registering someone while the internet is
--  down would both hand out file 148 if the device could choose. So a patient
--  arrives here with a real id and a null file_no, and leaves with a number.
-- ---------------------------------------------------------------------------
create or replace function clinic.sync_patient(p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = clinic, public as $$
declare
  v_id   uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_name text := nullif(trim(p_payload ->> 'full_name'), '');
  v_file bigint;
begin
  if not clinic.is_staff() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if v_id is null then
    raise exception 'BAD_PAYLOAD' using errcode = 'P0001';
  end if;
  if v_name is null then
    raise exception 'NAME_REQUIRED' using errcode = 'P0001';
  end if;

  select file_no into v_file from clinic.patients where id = v_id;

  insert into clinic.patients (
    id, file_no, full_name, phone, gender, birth_date,
    address_ar, allergies_ar, chronic_ar, notes_ar, created_by
  ) values (
    v_id,
    coalesce(v_file, nextval('clinic.patient_file_seq')),
    v_name,
    nullif(p_payload ->> 'phone',''),
    nullif(p_payload ->> 'gender',''),
    nullif(p_payload ->> 'birth_date','')::date,
    nullif(p_payload ->> 'address_ar',''),
    nullif(p_payload ->> 'allergies_ar',''),
    nullif(p_payload ->> 'chronic_ar',''),
    nullif(p_payload ->> 'notes_ar',''),
    auth.uid()
  )
  on conflict (id) do update set
    full_name    = excluded.full_name,
    phone        = excluded.phone,
    gender       = excluded.gender,
    birth_date   = excluded.birth_date,
    address_ar   = excluded.address_ar,
    allergies_ar = excluded.allergies_ar,
    chronic_ar   = excluded.chronic_ar,
    notes_ar     = excluded.notes_ar;

  select file_no into v_file from clinic.patients where id = v_id;
  return jsonb_build_object('id', v_id, 'file_no', v_file);
end $$;

-- ---------------------------------------------------------------------------
--  البحث — بالاسم العربي أو بالموبايل
--
--  Both sides of the comparison are folded by the same rule: `name_key` is a
--  generated column running public.fold_arabic(), and the term is folded here
--  by the same function. web/lib/arabic.js folds it a third time for the
--  device's offline search, and tools/schema-check/verify.mjs asserts all
--  three agree — without that, "أحمد" filed on one keyboard is unfindable from
--  another typing "احمد".
-- ---------------------------------------------------------------------------
create or replace function clinic.search_patients(p_term text, p_limit int default 30)
returns table (
  id uuid, file_no bigint, full_name text, phone text,
  gender text, birth_date date, allergies_ar text, chronic_ar text,
  last_visit timestamptz
)
language sql stable security definer set search_path = clinic, public as $$
  select p.id, p.file_no, p.full_name, p.phone,
         p.gender, p.birth_date, p.allergies_ar, p.chronic_ar,
         (select max(v.created_at) from clinic.visits v where v.patient_id = p.id)
    from clinic.patients p
   where clinic.is_staff()
     and (
       nullif(trim(coalesce(p_term,'')), '') is null
       or p.name_key like '%' || public.fold_arabic(trim(p_term)) || '%'
       or p.phone like public.normalize_phone(p_term) || '%'
       or p.file_no::text = regexp_replace(coalesce(p_term,''), '[^0-9]', '', 'g')
     )
   order by p.updated_at desc
   limit greatest(1, least(coalesce(p_limit, 30), 100))
$$;

-- ---------------------------------------------------------------------------
--  الزيارة والطابور
-- ---------------------------------------------------------------------------

-- Which fee applies. The receptionist argues about this every day; here it is
-- one rule, read from settings, snapshotted onto the visit at booking time so
-- that raising the price next month does not rewrite this month's paperwork.
create or replace function clinic.suggest_fee(p_patient uuid)
returns jsonb
language sql stable security definer set search_path = clinic, public as $$
  select case when not clinic.is_staff() then null else (
    select case
      when exists (
        select 1 from clinic.visits v
         where v.patient_id = p_patient
           and v.status = 'done'
           and v.created_at >= now() - (s.follow_up_days || ' days')::interval
      ) then jsonb_build_object('kind', 'follow_up', 'fee', s.follow_up_fee)
      else jsonb_build_object('kind', 'new', 'fee', s.consult_fee)
    end
    from clinic.settings s where s.id
  ) end
$$;

create or replace function clinic.book_visit(
  p_patient uuid,
  p_doctor  uuid,
  p_when    timestamptz default null
) returns uuid
language plpgsql security definer set search_path = clinic, public as $$
declare v_id uuid := gen_random_uuid(); v_sug jsonb;
begin
  if not clinic.is_staff() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if not exists (select 1 from clinic.patients where id = p_patient) then
    raise exception 'NO_PATIENT' using errcode = 'P0001';
  end if;
  if p_doctor is not null and not exists (
       select 1 from clinic.staff
        where id = p_doctor and is_active and role in ('doctor','director')) then
    raise exception 'NO_DOCTOR' using errcode = 'P0001';
  end if;

  v_sug := clinic.suggest_fee(p_patient);

  insert into clinic.visits (id, patient_id, doctor_id, scheduled_at, status, kind, fee, created_by)
  values (
    v_id, p_patient, p_doctor, coalesce(p_when, now()),
    case when p_when is null or p_when <= now() then 'waiting' else 'booked' end,
    (v_sug ->> 'kind')::clinic.visit_kind,
    (v_sug ->> 'fee')::numeric,
    auth.uid()
  );

  if p_when is null or p_when <= now() then
    update clinic.visits set arrived_at = now() where id = v_id;
  end if;

  return v_id;
end $$;

-- The status machine. In a FUNCTION and not an UPDATE policy, for the reason
-- 20260810100009_orders.sql:13 gives: a policy can say who may write, only a
-- function can say which move is legal.
create or replace function clinic.set_visit_status(p_id uuid, p_status clinic.visit_status)
returns void
language plpgsql security definer set search_path = clinic, public as $$
declare v_old clinic.visit_status;
begin
  if not clinic.is_staff() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;

  select status into v_old from clinic.visits where id = p_id;
  if v_old is null then
    raise exception 'NO_VISIT' using errcode = 'P0001';
  end if;
  if v_old in ('done','cancelled','no_show') then
    raise exception 'VISIT_FINAL' using errcode = 'P0001';
  end if;

  if not (
    (v_old = 'booked'  and p_status in ('waiting','cancelled','no_show')) or
    (v_old = 'waiting' and p_status in ('in_room','cancelled','no_show')) or
    (v_old = 'in_room' and p_status in ('done','waiting'))
  ) then
    raise exception 'VISIT_TRANSITION_NOT_ALLOWED' using errcode = 'P0001';
  end if;

  update clinic.visits
     set status     = p_status,
         arrived_at = case when p_status = 'waiting' then coalesce(arrived_at, now())
                           else arrived_at end,
         started_at = case when p_status = 'in_room' then coalesce(started_at, now())
                           else started_at end,
         ended_at   = case when p_status = 'done' then now() else ended_at end
   where id = p_id;
end $$;

-- طابور النهارده. Reception sees the whole board; a doctor sees the whole
-- board too — knowing three people are waiting for a colleague is how a clinic
-- decides who takes the next walk-in.
create or replace function clinic.today_queue()
returns table (
  visit_id uuid, patient_id uuid, file_no bigint, full_name text, phone text,
  doctor_id uuid, doctor_name text,
  status clinic.visit_status, kind clinic.visit_kind, fee numeric,
  scheduled_at timestamptz, arrived_at timestamptz,
  paid numeric
)
language sql stable security definer set search_path = clinic, public as $$
  select v.id, p.id, p.file_no, p.full_name, p.phone,
         v.doctor_id, s.display_name,
         v.status, v.kind, v.fee,
         v.scheduled_at, v.arrived_at,
         coalesce((select sum(y.amount) from clinic.payments y where y.visit_id = v.id), 0)
    from clinic.visits v
    join clinic.patients p on p.id = v.patient_id
    left join clinic.staff s on s.id = v.doctor_id
   where clinic.is_staff()
     and coalesce(v.scheduled_at, v.created_at)::date = current_date
   order by
     array_position(array['in_room','waiting','booked','done','no_show','cancelled']::text[],
                    v.status::text),
     coalesce(v.arrived_at, v.scheduled_at, v.created_at)
$$;

-- The numbers on the home screen. Same shape as public.admin_dashboard().
create or replace function clinic.clinic_home()
returns jsonb
language sql stable security definer set search_path = clinic, public as $$
  select case when not clinic.is_staff() then null else jsonb_build_object(
    'waiting',   (select count(*) from clinic.visits
                   where status = 'waiting'
                     and coalesce(scheduled_at, created_at)::date = current_date),
    'in_room',   (select count(*) from clinic.visits
                   where status = 'in_room'
                     and coalesce(scheduled_at, created_at)::date = current_date),
    'mine_today',(select count(*) from clinic.visits
                   where doctor_id = auth.uid()
                     and coalesce(scheduled_at, created_at)::date = current_date),
    'done_today',(select count(*) from clinic.visits
                   where status = 'done'
                     and coalesce(scheduled_at, created_at)::date = current_date),
    'patients',  (select count(*) from clinic.patients),
    -- Registered while offline and never reviewed for a duplicate. Reception
    -- clears this; a silent duplicate file is how a patient's history splits
    -- in two and never comes back together.
    'unreviewed',(select count(*) from clinic.patients p
                   where exists (select 1 from clinic.patients q
                                  where q.id <> p.id
                                    and q.name_key = p.name_key
                                    and coalesce(q.phone,'') = coalesce(p.phone,'')))
  ) end
$$;

-- ---------------------------------------------------------------- grants ---

revoke execute on function clinic.sync_patient(jsonb)                         from public, anon;
revoke execute on function clinic.search_patients(text, int)                  from public, anon;
revoke execute on function clinic.suggest_fee(uuid)                           from public, anon;
revoke execute on function clinic.book_visit(uuid, uuid, timestamptz)         from public, anon;
revoke execute on function clinic.set_visit_status(uuid, clinic.visit_status) from public, anon;
revoke execute on function clinic.today_queue()                               from public, anon;
revoke execute on function clinic.clinic_home()                               from public, anon;

grant execute on function clinic.sync_patient(jsonb)                         to authenticated;
grant execute on function clinic.search_patients(text, int)                  to authenticated;
grant execute on function clinic.suggest_fee(uuid)                           to authenticated;
grant execute on function clinic.book_visit(uuid, uuid, timestamptz)         to authenticated;
grant execute on function clinic.set_visit_status(uuid, clinic.visit_status) to authenticated;
grant execute on function clinic.today_queue()                               to authenticated;
grant execute on function clinic.clinic_home()                               to authenticated;

-- ## 20260812100004_clinic_billing.sql
-- ============================================================================
--  العيادة — الفلوس وتقارير الديريكتور
--
--  ⚠  Sorts AFTER 20260810100006_rls.sql. Carries its own grants, at the
--     bottom.
--
--  The director's question is one sentence — "مين كشف لمين، وإيه اللي اتكتب" —
--  and it is answered by two functions here. Both refuse anyone who is not the
--  director, INSIDE the function, rather than by hoping the panel hides a menu
--  item. RLS already stops a doctor reading a colleague's payments; these add
--  the aggregate view that RLS cannot express.
-- ============================================================================

create or replace function clinic.take_payment(
  p_visit  uuid,
  p_amount numeric,
  p_method clinic.pay_method default 'cash',
  p_note   text default null
) returns uuid
language plpgsql security definer set search_path = clinic, public as $$
declare v_id uuid := gen_random_uuid();
begin
  -- The doctor does not handle the money. Reception does, and the director
  -- covers reception on their day off.
  if not (clinic.is_reception() or clinic.is_director()) then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if coalesce(p_amount, 0) <= 0 then
    raise exception 'BAD_AMOUNT' using errcode = 'P0001';
  end if;
  if not exists (select 1 from clinic.visits where id = p_visit) then
    raise exception 'NO_VISIT' using errcode = 'P0001';
  end if;

  insert into clinic.payments (id, visit_id, amount, method, received_by, note_ar)
  values (v_id, p_visit, p_amount, coalesce(p_method, 'cash'), auth.uid(), nullif(trim(p_note),''));

  insert into clinic.audit_events (actor_id, action, entity, entity_id, detail)
  values (auth.uid(), 'took_payment', 'payments', v_id,
          jsonb_build_object('visit', p_visit, 'amount', p_amount));

  return v_id;
end $$;

-- ---------------------------------------------------------------------------
--  تقرير اليوم — الدرج في آخر اليوم
--
--  Reception balances the cash box against this. The doctor's own line is
--  visible to them; the whole sheet is reception's and the director's.
-- ---------------------------------------------------------------------------
create or replace function clinic.day_sheet(p_day date default current_date)
returns jsonb
language sql stable security definer set search_path = clinic, public as $$
  select case when not clinic.is_staff() then null else jsonb_build_object(
    'day', p_day,
    'visits',   (select count(*) from clinic.visits v
                  where coalesce(v.scheduled_at, v.created_at)::date = p_day
                    and v.status = 'done'),
    -- What the visits SHOULD have brought in…
    'due',      (select coalesce(sum(v.fee), 0) from clinic.visits v
                  where coalesce(v.scheduled_at, v.created_at)::date = p_day
                    and v.status = 'done'),
    -- …and what actually reached the drawer. The gap is the number worth
    -- looking at; showing only one of the two hides it.
    'collected',(select coalesce(sum(y.amount), 0) from clinic.payments y
                  where y.created_at::date = p_day),
    'by_method',(select coalesce(jsonb_object_agg(m, t), '{}'::jsonb) from (
                   select method::text as m, sum(amount) as t
                     from clinic.payments where created_at::date = p_day
                    group by method) q)
  ) end
$$;

-- ---------------------------------------------------------------------------
--  الديريكتور: كل دكتور كشف كام، وحصّل كام
-- ---------------------------------------------------------------------------
create or replace function clinic.report_by_doctor(
  p_from date default current_date,
  p_to   date default current_date
) returns table (
  doctor_id     uuid,
  doctor_name   text,
  visits        bigint,
  patients      bigint,
  encounters    bigint,
  prescriptions bigint,
  due           numeric,
  collected     numeric
)
language sql stable security definer set search_path = clinic, public as $$
  select s.id, s.display_name,
         (select count(*) from clinic.visits v
           where v.doctor_id = s.id and v.status = 'done'
             and coalesce(v.scheduled_at, v.created_at)::date between p_from and p_to),
         (select count(distinct v.patient_id) from clinic.visits v
           where v.doctor_id = s.id
             and coalesce(v.scheduled_at, v.created_at)::date between p_from and p_to),
         (select count(*) from clinic.encounters e
           where e.doctor_id = s.id and e.created_at::date between p_from and p_to),
         (select count(*) from clinic.prescriptions r
           where r.doctor_id = s.id and r.status = 'issued'
             and r.written_at::date between p_from and p_to),
         (select coalesce(sum(v.fee), 0) from clinic.visits v
           where v.doctor_id = s.id and v.status = 'done'
             and coalesce(v.scheduled_at, v.created_at)::date between p_from and p_to),
         (select coalesce(sum(y.amount), 0)
            from clinic.payments y join clinic.visits v on v.id = y.visit_id
           where v.doctor_id = s.id and y.created_at::date between p_from and p_to)
    from clinic.staff s
   where clinic.is_director()
     and s.role in ('doctor','director')
   order by s.display_name
$$;

-- ---------------------------------------------------------------------------
--  الديريكتور: مين كشف لمين، وإيه الروشتة اللي اتكتبت
--
--  The row-per-prescription view behind the report screen. Includes the lines,
--  because "الروشتات اللي انكتبت" without the drugs on them answers nothing.
-- ---------------------------------------------------------------------------
create or replace function clinic.report_prescriptions(
  p_from   date default current_date,
  p_to     date default current_date,
  p_doctor uuid default null
) returns table (
  rx_id       uuid,
  rx_no       text,
  written_at  timestamptz,
  status      clinic.record_status,
  doctor_id   uuid,
  doctor_name text,
  patient_id  uuid,
  file_no     bigint,
  patient_name text,
  diagnosis_ar text,
  amended_from uuid,
  items       jsonb
)
language sql stable security definer set search_path = clinic, public as $$
  select r.id, r.rx_no, r.written_at, r.status,
         r.doctor_id, s.display_name,
         p.id, p.file_no, p.full_name,
         e.diagnosis_ar,
         r.amended_from,
         coalesce((select jsonb_agg(to_jsonb(i) order by i.line_no)
                     from clinic.prescription_items i where i.rx_id = r.id), '[]'::jsonb)
    from clinic.prescriptions r
    join clinic.staff    s on s.id = r.doctor_id
    join clinic.patients p on p.id = r.patient_id
    left join clinic.encounters e on e.id = r.encounter_id
   where clinic.is_director()
     and r.written_at::date between p_from and p_to
     and (p_doctor is null or r.doctor_id = p_doctor)
   order by r.written_at desc
$$;

-- ---------------------------------------------------------------- grants ---

revoke execute on function clinic.take_payment(uuid, numeric, clinic.pay_method, text) from public, anon;
revoke execute on function clinic.day_sheet(date)                        from public, anon;
revoke execute on function clinic.report_by_doctor(date, date)           from public, anon;
revoke execute on function clinic.report_prescriptions(date, date, uuid) from public, anon;

grant execute on function clinic.take_payment(uuid, numeric, clinic.pay_method, text) to authenticated;
grant execute on function clinic.day_sheet(date)                        to authenticated;
grant execute on function clinic.report_by_doctor(date, date)           to authenticated;
grant execute on function clinic.report_prescriptions(date, date, uuid) to authenticated;

-- ## 20260812100005_clinic_catalog.sql
-- ============================================================================
--  العيادة — كتالوج الأدوية والتحاليل
--
--  ⚠  Sorts AFTER 20260810100006_rls.sql. Carries its own grants, at the
--     bottom.
--
--  THE CATALOGUE IS DOWNLOADED WHOLE ONTO EVERY CLINIC DEVICE.
--
--  That is the entire reason "type one letter, see the drug" is instant and
--  keeps working when the clinic's internet drops. A server-side search would
--  be both slower on every keystroke AND the first thing to fail at the moment
--  it is needed most.
--
--  So the sync has to be cheap to repeat: clinic.drug_catalog(since) returns
--  only rows touched after `since`, plus the catalogue version from settings.
--  First run pulls everything; every run after that pulls almost nothing.
-- ============================================================================

-- Any change to the catalogue bumps the version, so a device holding a stale
-- copy can tell without diffing a few thousand rows.
create or replace function clinic.bump_catalog_version()
returns trigger
language plpgsql set search_path = clinic, public as $$
begin
  update clinic.settings set drug_catalog_version = drug_catalog_version + 1 where id;
  return null;
end $$;

drop trigger if exists drugs_bump_version on clinic.drugs;
create trigger drugs_bump_version after insert or update or delete on clinic.drugs
  for each statement execute function clinic.bump_catalog_version();

-- ---------------------------------------------------------------------------
--  المزامنة — اللي اتغيّر بس
--
--  Deletions are handled by is_active rather than DELETE: a device that never
--  hears about a removed row would otherwise keep offering a drug the clinic
--  has withdrawn. A row flipped inactive still arrives in the delta and the
--  device drops it locally.
-- ---------------------------------------------------------------------------
create or replace function clinic.drug_catalog(p_since timestamptz default null)
returns jsonb
language sql stable security definer set search_path = clinic, public as $$
  select case when not clinic.is_staff() then null else jsonb_build_object(
    'version', (select drug_catalog_version from clinic.settings where id),
    'now',     now(),
    'drugs',   coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', d.id, 'trade_name', d.trade_name,
               'trade_name_ar', d.trade_name_ar,
               'generic_ar', d.generic_ar, 'generic_en', d.generic_en,
               'form_ar', d.form_ar, 'strength', d.strength,
               'name_key', d.name_key, 'is_active', d.is_active))
        from clinic.drugs d
       where p_since is null or d.updated_at > p_since), '[]'::jsonb),
    -- This doctor's own habits, so the picker can float what they actually
    -- prescribe to the top without a second round trip.
    'usage',   coalesce((
      select jsonb_object_agg(u.drug_id::text, u.uses)
        from clinic.drug_usage u where u.doctor_id = auth.uid()), '{}'::jsonb),
    'tests',   coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', t.id, 'name_ar', t.name_ar, 'name_en', t.name_en,
               'category', t.category, 'name_key', t.name_key,
               'is_active', t.is_active))
        from clinic.lab_tests t
       where p_since is null or t.updated_at > p_since), '[]'::jsonb)
  ) end
$$;

-- Adding a drug that is not in the list, from the prescription screen, without
-- leaving it. A catalogue nobody can extend at the moment of need is a
-- catalogue people work around by typing free text, and free text is what the
-- snapshot columns exist to avoid depending on.
create or replace function clinic.add_drug(
  p_trade_name    text,
  p_generic_ar    text default null,
  p_form_ar       text default '',
  p_strength      text default '',
  p_trade_name_ar text default ''
) returns uuid
language plpgsql security definer set search_path = clinic, public as $$
declare v_id uuid; v_name text := nullif(trim(coalesce(p_trade_name,'')), '');
begin
  if not clinic.is_clinician() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if v_name is null then
    raise exception 'NAME_REQUIRED' using errcode = 'P0001';
  end if;

  insert into clinic.drugs (trade_name, trade_name_ar, generic_ar, form_ar, strength)
  values (v_name, coalesce(trim(p_trade_name_ar), ''),
          nullif(trim(coalesce(p_generic_ar,'')),''),
          coalesce(trim(p_form_ar), ''), coalesce(trim(p_strength), ''))
  on conflict (trade_name, strength, form_ar) do update
    set is_active = true                    -- re-adding a withdrawn one revives it
  returning id into v_id;

  return v_id;
end $$;

-- ============================================================================
--  البذرة — أدوية شائعة في السوق المصري
--
--  A STARTING POINT, not a formulary. It exists so the picker is useful on day
--  one instead of empty, and every row is editable from the screen. The
--  clinic's own list — the drugs this doctor actually writes — is a better
--  seed than this one by a wide margin, and replacing it is a paste into the
--  drugs screen, not a migration.
--
--  Re-runnable: `on conflict do nothing`, keyed on (trade_name, strength,
--  form_ar).
-- ============================================================================
insert into clinic.drugs (trade_name, generic_ar, generic_en, form_ar, strength) values
  -- مسكنات وخافضات حرارة
  ('Panadol',      'باراسيتامول',            'Paracetamol',            'أقراص', '500 مجم'),
  ('Panadol Extra','باراسيتامول وكافيين',    'Paracetamol/Caffeine',   'أقراص', '500 مجم'),
  ('Adol',         'باراسيتامول',            'Paracetamol',            'أقراص', '500 مجم'),
  ('Abimol',       'باراسيتامول',            'Paracetamol',            'شراب',  '120 مجم/5 مل'),
  ('Cataflam',     'ديكلوفيناك بوتاسيوم',    'Diclofenac Potassium',   'أقراص', '50 مجم'),
  ('Voltaren',     'ديكلوفيناك صوديوم',      'Diclofenac Sodium',      'أمبول', '75 مجم'),
  ('Rofenac',      'ديكلوفيناك صوديوم',      'Diclofenac Sodium',      'أقراص', '50 مجم'),
  ('Brufen',       'إيبوبروفين',             'Ibuprofen',              'أقراص', '400 مجم'),
  ('Brufen',       'إيبوبروفين',             'Ibuprofen',              'شراب',  '100 مجم/5 مل'),
  ('Ketolac',      'كيتورولاك',              'Ketorolac',              'أمبول', '30 مجم'),
  ('Ketofan',      'كيتوبروفين',             'Ketoprofen',             'أقراص', '100 مجم'),
  ('Myofen',       'إيبوبروفين وباراسيتامول','Ibuprofen/Paracetamol',  'أقراص', ''),

  -- مضادات حيوية
  ('Augmentin',    'أموكسيسيللين وكلافولانيك','Amoxicillin/Clavulanate','أقراص','1 جم'),
  ('Augmentin',    'أموكسيسيللين وكلافولانيك','Amoxicillin/Clavulanate','شراب', '457 مجم/5 مل'),
  ('Hibiotic',     'أموكسيسيللين وكلافولانيك','Amoxicillin/Clavulanate','أقراص','1 جم'),
  ('Amoxil',       'أموكسيسيللين',           'Amoxicillin',            'كبسول','500 مجم'),
  ('Unictam',      'أمبيسيللين وسلباكتام',   'Ampicillin/Sulbactam',   'فيال', '1.5 جم'),
  ('Zithromax',    'أزيثرومايسين',           'Azithromycin',           'أقراص','500 مجم'),
  ('Zisrocin',     'أزيثرومايسين',           'Azithromycin',           'شراب', '200 مجم/5 مل'),
  ('Klaricid',     'كلاريثرومايسين',         'Clarithromycin',         'أقراص','500 مجم'),
  ('Ciprocin',     'سيبروفلوكساسين',         'Ciprofloxacin',          'أقراص','500 مجم'),
  ('Tavanic',      'ليفوفلوكساسين',          'Levofloxacin',           'أقراص','500 مجم'),
  ('Cefotax',      'سيفوتاكسيم',             'Cefotaxime',             'فيال', '1 جم'),
  ('Ceftriaxone',  'سيفترياكسون',            'Ceftriaxone',            'فيال', '1 جم'),
  ('Zinnat',       'سيفوروكسيم',             'Cefuroxime',             'أقراص','500 مجم'),
  ('Flagyl',       'ميترونيدازول',           'Metronidazole',          'أقراص','500 مجم'),
  ('Amrizole',     'ميترونيدازول',           'Metronidazole',          'شراب', '125 مجم/5 مل'),
  ('Doxymycin',    'دوكسيسيكلين',            'Doxycycline',            'كبسول','100 مجم'),

  -- الجهاز الهضمي
  ('Nexium',       'إيزوميبرازول',           'Esomeprazole',           'أقراص','40 مجم'),
  ('Controloc',    'بانتوبرازول',            'Pantoprazole',           'أقراص','40 مجم'),
  ('Omez',         'أوميبرازول',             'Omeprazole',             'كبسول','20 مجم'),
  ('Motilium',     'دومبيريدون',             'Domperidone',            'أقراص','10 مجم'),
  ('Primperan',    'ميتوكلوبراميد',          'Metoclopramide',         'أمبول','10 مجم'),
  ('Buscopan',     'هيوسين بيوتيل بروميد',   'Hyoscine Butylbromide',  'أقراص','10 مجم'),
  ('Spasmo-Digestin','إنزيمات هاضمة',        'Digestive Enzymes',      'أقراص',''),
  ('Antinal',      'نيفوروكسازيد',           'Nifuroxazide',           'كبسول','200 مجم'),
  ('Smecta',       'ديوسميكتيت',             'Diosmectite',            'أكياس','3 جم'),
  ('Duphalac',     'لاكتيولوز',              'Lactulose',              'شراب', '10 جم/15 مل'),
  ('Gaviscon',     'ألجينات الصوديوم',       'Sodium Alginate',        'شراب', ''),
  ('Epicogel',     'مضاد حموضة',             'Antacid',                'شراب', ''),
  ('Colona',       'ميبيفيرين',              'Mebeverine',             'كبسول','200 مجم'),

  -- الحساسية والجهاز التنفسي
  ('Telfast',      'فيكسوفينادين',           'Fexofenadine',           'أقراص','180 مجم'),
  ('Claritine',    'لوراتادين',              'Loratadine',             'أقراص','10 مجم'),
  ('Zyrtec',       'سيتريزين',               'Cetirizine',             'أقراص','10 مجم'),
  ('Allergyl',     'كلورفينيرامين',          'Chlorpheniramine',       'شراب', ''),
  ('Ventolin',     'سالبيوتامول',            'Salbutamol',             'بخاخ', '100 ميكروجم'),
  ('Ventolin',     'سالبيوتامول',            'Salbutamol',             'محلول بخار','5 مجم/مل'),
  ('Flixotide',    'فلوتيكازون',             'Fluticasone',            'بخاخ', '125 ميكروجم'),
  ('Symbicort',    'بوديزونيد وفورموتيرول',  'Budesonide/Formoterol',  'بخاخ', ''),
  ('Mucosolvan',   'أمبروكسول',              'Ambroxol',               'شراب', '30 مجم/5 مل'),
  ('Fluimucil',    'أسيتيل سيستئين',         'Acetylcysteine',         'أكياس','200 مجم'),
  ('Otrivin',      'زيلوميتازولين',          'Xylometazoline',         'نقط أنف',''),
  ('Congestal',    'مضاد احتقان',            'Decongestant',           'أقراص',''),

  -- القلب والضغط والدهون
  ('Concor',       'بيسوبرولول',             'Bisoprolol',             'أقراص','5 مجم'),
  ('Tritace',      'راميبريل',               'Ramipril',               'أقراص','5 مجم'),
  ('Norvasc',      'أملوديبين',              'Amlodipine',             'أقراص','5 مجم'),
  ('Capoten',      'كابتوبريل',              'Captopril',              'أقراص','25 مجم'),
  ('Lasix',        'فوروسيميد',              'Furosemide',             'أقراص','40 مجم'),
  ('Aspocid',      'أسبرين',                 'Aspirin',                'أقراص','75 مجم'),
  ('Plavix',       'كلوبيدوجريل',            'Clopidogrel',            'أقراص','75 مجم'),
  ('Lipitor',      'أتورفاستاتين',           'Atorvastatin',           'أقراص','20 مجم'),
  ('Crestor',      'روسوفاستاتين',           'Rosuvastatin',           'أقراص','10 مجم'),

  -- السكر والغدة
  ('Glucophage',   'ميتفورمين',              'Metformin',              'أقراص','850 مجم'),
  ('Amaryl',       'جليمبيريد',              'Glimepiride',            'أقراص','2 مجم'),
  ('Januvia',      'سيتاجليبتين',            'Sitagliptin',            'أقراص','100 مجم'),
  ('Lantus',       'إنسولين جلارجين',        'Insulin Glargine',       'قلم',  '100 وحدة/مل'),
  ('Mixtard',      'إنسولين مخلوط',          'Insulin Mixed',          'قلم',  '100 وحدة/مل'),
  ('Eltroxin',     'ليفوثيروكسين',           'Levothyroxine',          'أقراص','50 ميكروجم'),

  -- فيتامينات ومعادن
  ('Vidrop',       'فيتامين د',              'Vitamin D3',             'نقط', ''),
  ('Devarol-S',    'فيتامين د',              'Vitamin D3',             'أمبول','200000 وحدة'),
  ('Ossofortin',   'كالسيوم وفيتامين د',     'Calcium/Vitamin D',      'أقراص',''),
  ('Ferrofol',     'حديد وحمض فوليك',        'Iron/Folic Acid',        'كبسول',''),
  ('Neurorubine',  'فيتامين ب المركب',       'Vitamin B Complex',      'أقراص',''),
  ('Depovit B12',  'فيتامين ب ١٢',           'Vitamin B12',            'أمبول',''),
  ('Zincoral',     'زنك',                    'Zinc',                   'شراب', ''),

  -- الأعصاب والنفسية
  ('Lyrica',       'بريجابالين',             'Pregabalin',             'كبسول','75 مجم'),
  ('Neurontin',    'جابابنتين',              'Gabapentin',             'كبسول','300 مجم'),
  ('Depakine',     'صوديوم فالبروات',        'Sodium Valproate',       'أقراص','500 مجم'),
  ('Tegretol',     'كاربامازيبين',           'Carbamazepine',          'أقراص','200 مجم'),
  ('Cipralex',     'إيسيتالوبرام',           'Escitalopram',           'أقراص','10 مجم'),
  ('Prozac',       'فلوكسيتين',              'Fluoxetine',             'كبسول','20 مجم'),
  ('Xanax',        'ألبرازولام',             'Alprazolam',             'أقراص','0.5 مجم'),
  ('Mydocalm',     'تولبيريزون',             'Tolperisone',            'أقراص','150 مجم'),
  ('Myogesic',     'مرخي عضلات ومسكن',       'Muscle Relaxant',        'أقراص',''),

  -- كورتيزون وإنزيمات وموضعي
  ('Solu-Medrol',  'ميثيل بريدنيزولون',      'Methylprednisolone',     'فيال', '40 مجم'),
  ('Hydrocortisone','هيدروكورتيزون',         'Hydrocortisone',         'فيال', '100 مجم'),
  ('Alphintern',   'إنزيمات مضادة للالتهاب', 'Trypsin/Chymotrypsin',   'أقراص',''),
  ('Fucidin',      'حمض الفيوسيديك',         'Fusidic Acid',           'كريم', ''),
  ('Fucicort',     'فيوسيديك وبيتاميثازون',  'Fusidic/Betamethasone',  'كريم', ''),
  ('Kenacomb',     'مرهم مركب',              'Combination Ointment',   'مرهم', ''),
  ('Canesten',     'كلوتريمازول',            'Clotrimazole',           'كريم', ''),
  ('Diflucan',     'فلوكونازول',             'Fluconazole',            'كبسول','150 مجم'),
  ('Nystatin',     'نيستاتين',               'Nystatin',               'معلق', ''),
  ('Zovirax',      'أسيكلوفير',              'Aciclovir',              'أقراص','400 مجم'),

  -- المسالك والنساء
  ('Uvamin',       'نيتروفورانتوين',         'Nitrofurantoin',         'كبسول','100 مجم'),
  ('Rowatinex',    'زيوت طيارة',             'Terpene Combination',    'كبسول',''),
  ('Duphaston',    'ديدروجستيرون',           'Dydrogesterone',         'أقراص','10 مجم'),
  ('Cyclo-Progynova','هرمونات بديلة',        'Estradiol/Norgestrel',   'أقراص','')
on conflict (trade_name, strength, form_ar) do nothing;

-- ---------------------------------------------------------------------------
--  الأسماء التجارية بالعربي
--
--  ⚠ THIS BLOCK IS NOT COSMETIC. Egyptian doctors prescribe by brand, and many
--    of them type Arabic. Without these spellings the search box answers
--    "كونكور" with nothing while holding Concor, and "فلاجيل" with nothing
--    while holding Flagyl — the drug is in the catalogue and simply cannot be
--    found by the words the doctor used.
--
--  Kept as a separate UPDATE rather than a sixth column on the INSERT above so
--  that the list reads as what it is: a spelling map, extendable one line at a
--  time by whoever notices a name that will not come up.
-- ---------------------------------------------------------------------------
update clinic.drugs d set trade_name_ar = v.ar
  from (values
    ('Panadol','بانادول'), ('Panadol Extra','بانادول إكسترا'), ('Adol','أدول'),
    ('Abimol','أبيمول'), ('Cataflam','كتافلام'), ('Voltaren','فولتارين'),
    ('Rofenac','روفيناك'), ('Brufen','بروفين'), ('Ketolac','كيتولاك'),
    ('Ketofan','كيتوفان'), ('Myofen','مايوفين'),

    ('Augmentin','أوجمنتين'), ('Hibiotic','هاي بيوتك'), ('Amoxil','أموكسيل'),
    ('Unictam','يونيكتام'), ('Zithromax','زيثروماكس'), ('Zisrocin','زيسروسين'),
    ('Klaricid','كلاريسيد'), ('Ciprocin','سيبروسين'), ('Tavanic','تافانيك'),
    ('Cefotax','سيفوتاكس'), ('Ceftriaxone','سيفترياكسون'), ('Zinnat','زينات'),
    ('Flagyl','فلاجيل'), ('Amrizole','أمريزول'), ('Doxymycin','دوكسيميسين'),

    ('Nexium','نيكسيوم'), ('Controloc','كونترولوك'), ('Omez','أوميز'),
    ('Motilium','موتيليوم'), ('Primperan','بريمبران'), ('Buscopan','بوسكوبان'),
    ('Spasmo-Digestin','سبازمو ديچستين'), ('Antinal','أنتينال'),
    ('Smecta','سميكتا'), ('Duphalac','دوفالاك'), ('Gaviscon','جافيسكون'),
    ('Epicogel','إبيكوجيل'), ('Colona','كولونا'),

    ('Telfast','تلفاست'), ('Claritine','كلاريتين'), ('Zyrtec','زيرتك'),
    ('Allergyl','أليرجيل'), ('Ventolin','فنتولين'), ('Flixotide','فليكسوتايد'),
    ('Symbicort','سيمبيكورت'), ('Mucosolvan','ميوكوسولفان'),
    ('Fluimucil','فلوموسيل'), ('Otrivin','أوتريفين'), ('Congestal','كونجستال'),

    ('Concor','كونكور'), ('Tritace','تريتاس'), ('Norvasc','نورفاسك'),
    ('Capoten','كابوتين'), ('Lasix','لازيكس'), ('Aspocid','أسبوسيد'),
    ('Plavix','بلافكس'), ('Lipitor','ليبيتور'), ('Crestor','كريستور'),

    ('Glucophage','جلوكوفاج'), ('Amaryl','أماريل'), ('Januvia','جانوفيا'),
    ('Lantus','لانتوس'), ('Mixtard','ميكستارد'), ('Eltroxin','إلتروكسين'),

    ('Vidrop','فيدروب'), ('Devarol-S','ديفارول'), ('Ossofortin','أوسوفورتين'),
    ('Ferrofol','فيروفول'), ('Neurorubine','نيوروروبين'),
    ('Depovit B12','ديبوفيت'), ('Zincoral','زنكورال'),

    ('Lyrica','ليريكا'), ('Neurontin','نيورونتين'), ('Depakine','ديباكين'),
    ('Tegretol','تيجريتول'), ('Cipralex','سيبرالكس'), ('Prozac','بروزاك'),
    ('Xanax','زاناكس'), ('Mydocalm','ميدوكالم'), ('Myogesic','مايوجيسك'),

    ('Solu-Medrol','سولومدرول'), ('Hydrocortisone','هيدروكورتيزون'),
    ('Alphintern','ألفنترن'), ('Fucidin','فيوسيدين'), ('Fucicort','فيوسيكورت'),
    ('Kenacomb','كيناكومب'), ('Canesten','كانستين'), ('Diflucan','ديفلوكان'),
    ('Nystatin','نيستاتين'), ('Zovirax','زوفيراكس'),

    ('Uvamin','يوفامين'), ('Rowatinex','رواتينكس'), ('Duphaston','دوفاستون'),
    ('Cyclo-Progynova','سيكلو بروجينوفا')
  ) as v(name, ar)
 where d.trade_name = v.name and d.trade_name_ar = '';

-- ---------------------------------------------------------- تحاليل وأشعة ----
insert into clinic.lab_tests (name_ar, name_en, category) values
  ('صورة دم كاملة',            'CBC',                    'تحاليل'),
  ('سرعة الترسيب',             'ESR',                    'تحاليل'),
  ('بروتين سي التفاعلي',       'CRP',                    'تحاليل'),
  ('سكر صائم',                 'Fasting Blood Sugar',    'تحاليل'),
  ('سكر بعد الأكل بساعتين',    'Post-Prandial Sugar',    'تحاليل'),
  ('السكر التراكمي',           'HbA1c',                  'تحاليل'),
  ('وظائف كبد',                'Liver Function Tests',   'تحاليل'),
  ('وظائف كلى',                'Kidney Function Tests',  'تحاليل'),
  ('دهون كاملة',               'Lipid Profile',          'تحاليل'),
  ('حمض بوليك',                'Uric Acid',              'تحاليل'),
  ('وظائف غدة درقية',          'TSH / T3 / T4',          'تحاليل'),
  ('تحليل بول',                'Urine Analysis',         'تحاليل'),
  ('تحليل براز',               'Stool Analysis',         'تحاليل'),
  ('مزرعة بول',                'Urine Culture',          'تحاليل'),
  ('فيتامين د',                'Vitamin D (25-OH)',      'تحاليل'),
  ('فيتامين ب ١٢',             'Vitamin B12',            'تحاليل'),
  ('مخزون الحديد',             'Serum Ferritin',         'تحاليل'),
  ('صوديوم وبوتاسيوم',         'Serum Electrolytes',     'تحاليل'),
  ('أشعة عادية على الصدر',     'Chest X-Ray',            'أشعة'),
  ('أشعة عادية على البطن',     'Abdominal X-Ray',        'أشعة'),
  ('سونار على البطن والحوض',   'Abdominopelvic US',      'أشعة'),
  ('سونار على الغدة الدرقية',  'Thyroid US',             'أشعة'),
  ('دوبلر على الشرايين',       'Arterial Doppler',       'أشعة'),
  ('أشعة مقطعية',              'CT Scan',                'أشعة'),
  ('رنين مغناطيسي',            'MRI',                    'أشعة'),
  ('رسم قلب',                  'ECG',                    'وظائف'),
  ('إيكو على القلب',           'Echocardiography',       'وظائف'),
  ('وظائف تنفس',               'Spirometry',             'وظائف')
on conflict (name_ar, category) do nothing;

-- ---------------------------------------------------------------- grants ---

revoke execute on function clinic.drug_catalog(timestamptz)              from public, anon;
revoke execute on function clinic.add_drug(text, text, text, text, text) from public, anon;
revoke execute on function clinic.bump_catalog_version()                 from public, anon;

grant execute on function clinic.drug_catalog(timestamptz)        to authenticated;
grant execute on function clinic.add_drug(text, text, text, text, text) to authenticated;

-- ## 20260812100006_clinic_accounts.sql
-- ============================================================================
--  العيادة — الحسابات
--
--  ⚠  Sorts AFTER 20260810100006_rls.sql. Carries its own grants, at the
--     bottom.
--
--  Reuses public.create_account() rather than repeating it. That function
--  carries three traps that cost real time in a sibling project — GoTrue's
--  NOT-NULL token columns, the missing auth.identities row, and crypt() living
--  in `extensions` on hosted Supabase — and a second copy here would be a
--  second copy of those bugs waiting to be reintroduced.
--
--  It is REVOKED from every role, which is deliberate: it takes the role as an
--  argument, so a grant would be a way to mint a manager. The wrappers below
--  reach it anyway because SECURITY DEFINER runs them as the owner, which is
--  the same door public.admin_create_user() goes through.
--
--  NOTE ON THE SHOP ROLE. Clinic staff are created with public role
--  'customer' — meaning "no role in the SHOP". A doctor is not a shop manager
--  and must never reach /admin. Their real role is clinic.staff.role, and that
--  is the only role any policy in this schema reads.
-- ============================================================================

create or replace function clinic.create_staff(
  p_phone        text,
  p_full_name    text,
  p_password     text,
  p_role         clinic.staff_role,
  p_display_name text default null,
  p_title_ar     text default null,
  p_specialty_ar text default null,
  p_syndicate_no text default null,
  p_rx_prefix    text default null
) returns uuid
language plpgsql security definer set search_path = clinic, public as $$
declare
  v_id     uuid;
  v_prefix text := nullif(trim(coalesce(p_rx_prefix,'')), '');
  v_n      int;
begin
  if not clinic.is_director() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;

  -- Raises BAD_PHONE / NAME_REQUIRED / PASSWORD_TOO_SHORT / PHONE_TAKEN, and
  -- the clinic's error map translates them with the same wording the shop
  -- uses.
  v_id := public.create_account(p_phone, p_full_name, p_password, 'customer');

  if p_role <> 'reception' and v_prefix is null then
    -- Short, unique, and it prints inside a prescription number a pharmacist
    -- reads over the phone. Sequential rather than derived from the name: two
    -- doctors called أحمد would otherwise collide on their first day.
    select count(*) + 1 into v_n from clinic.staff where role in ('doctor','director');
    v_prefix := 'د' || v_n::text;
    while exists (select 1 from clinic.staff where rx_prefix = v_prefix) loop
      v_n := v_n + 1;
      v_prefix := 'د' || v_n::text;
    end loop;
  end if;

  insert into clinic.staff (
    id, role, display_name, title_ar, specialty_ar, syndicate_no, rx_prefix
  ) values (
    v_id, p_role,
    coalesce(nullif(trim(coalesce(p_display_name,'')), ''), trim(p_full_name)),
    nullif(trim(coalesce(p_title_ar,'')), ''),
    nullif(trim(coalesce(p_specialty_ar,'')), ''),
    nullif(trim(coalesce(p_syndicate_no,'')), ''),
    v_prefix
  );

  insert into clinic.audit_events (actor_id, action, entity, entity_id, detail)
  values (auth.uid(), 'created_staff', 'staff', v_id,
          jsonb_build_object('role', p_role::text));

  return v_id;
end $$;

-- ---------------------------------------------------------------------------
--  إيقاف حساب
--
--  Same two guards as public.admin_set_active(), for the same two reasons:
--  switching yourself off locks you out of your own clinic, and switching off
--  the last director leaves nobody who can switch anyone back on.
-- ---------------------------------------------------------------------------
create or replace function clinic.set_staff_active(p_id uuid, p_active boolean)
returns void
language plpgsql security definer set search_path = clinic, public as $$
begin
  if not clinic.is_director() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if p_id = auth.uid() then
    raise exception 'CANNOT_DISABLE_SELF' using errcode = 'P0001';
  end if;
  if not p_active and (
       select count(*) from clinic.staff
        where role = 'director' and is_active and id <> p_id) = 0 then
    raise exception 'LAST_DIRECTOR' using errcode = 'P0001';
  end if;

  update clinic.staff set is_active = p_active where id = p_id;
end $$;

-- A director resetting a doctor's password, or anyone changing their own.
-- public.admin_set_password() cannot serve this: it asks is_manager(), and a
-- director of the clinic is deliberately not a manager of the shop.
create or replace function clinic.set_staff_password(p_id uuid, p_password text)
returns void
language plpgsql security definer set search_path = clinic, public, extensions as $$
begin
  if not (clinic.is_director() or p_id = auth.uid()) then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if not exists (select 1 from clinic.staff where id = p_id) then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if length(coalesce(p_password, '')) < 6 then
    raise exception 'PASSWORD_TOO_SHORT' using errcode = 'P0001';
  end if;

  update auth.users
     set encrypted_password = crypt(p_password, gen_salt('bf')),
         updated_at = now()
   where id = p_id;

  perform public.fix_auth_user_tokens(p_id);
end $$;

-- The staff screen. Joins the phone off the profile, because that is the
-- username people sign in with and the director needs to read it back to
-- somebody who has forgotten it.
create or replace function clinic.staff_list()
returns table (
  id uuid, role clinic.staff_role, display_name text, phone text,
  title_ar text, specialty_ar text, syndicate_no text, rx_prefix text,
  is_active boolean, created_at timestamptz
)
language sql stable security definer set search_path = clinic, public as $$
  select s.id, s.role, s.display_name, p.phone,
         s.title_ar, s.specialty_ar, s.syndicate_no, s.rx_prefix,
         s.is_active, s.created_at
    from clinic.staff s
    join public.profiles p on p.id = s.id
   where clinic.is_director()
   order by s.role, s.display_name
$$;

-- Who am I, in one call the shell can make on load. Returns null for a signed
-- in user who does not work here — which is what the shop's own manager gets,
-- and correctly so.
create or replace function clinic.me()
returns jsonb
language sql stable security definer set search_path = clinic, public as $$
  select to_jsonb(s) || jsonb_build_object('phone', p.phone)
    from clinic.staff s
    join public.profiles p on p.id = s.id
   where s.id = auth.uid() and s.is_active
$$;

-- ---------------------------------------------------------------- grants ---

revoke execute on function clinic.create_staff(text, text, text, clinic.staff_role,
                                               text, text, text, text, text) from public, anon;
revoke execute on function clinic.set_staff_active(uuid, boolean)   from public, anon;
revoke execute on function clinic.set_staff_password(uuid, text)    from public, anon;
revoke execute on function clinic.staff_list()                      from public, anon;
revoke execute on function clinic.me()                              from public, anon;

grant execute on function clinic.create_staff(text, text, text, clinic.staff_role,
                                              text, text, text, text, text) to authenticated;
grant execute on function clinic.set_staff_active(uuid, boolean)   to authenticated;
grant execute on function clinic.set_staff_password(uuid, text)    to authenticated;
grant execute on function clinic.staff_list()                      to authenticated;
grant execute on function clinic.me()                              to authenticated;

-- ============================================================================
--  أول حساب ديريكتور
--
--  الموبايل 01000000009 وكلمة السر تحت.
--  ⚠  غيّر كلمة السر أول ما تدخل — الملف ده موجود في المستودع، فأي حد يقراه
--     يعرف كلمة السر دي. ودي بيانات مرضى.
--
--  Bypasses clinic.create_staff() because that one asks is_director(), and at
--  this instant there is nobody to be one.
--
--  ⚠ RESERVED SEED NUMBERS — profiles.phone is UNIQUE, so a collision here
--   fails the whole install with a constraint error nobody can read:
--     01000000000  the shop's first manager   (20260810100011_accounts.sql)
--     01000000001  the harness's test manager (tools/schema-check/verify.mjs)
--     01000000002  the harness's test customer
--     01000000009  ← this one
--
--  Re-runnable: a second run finds a director already there and does nothing.
-- ============================================================================
do $$
declare v_id uuid;
begin
  if not exists (select 1 from clinic.staff where role = 'director') then
    v_id := public.create_account('01000000009', 'مدير العيادة', 'clinic2026', 'customer');
    insert into clinic.staff (id, role, display_name, title_ar, rx_prefix)
    values (v_id, 'director', 'د. مدير العيادة', 'استشاري', 'د1')
    on conflict (id) do nothing;
  end if;
end $$;

-- ## 20260812100007_clinic_export.sql
-- ============================================================================
--  العيادة — تصدير نسخة احتياطية
--
--  ⚠  Sorts AFTER 20260810100006_rls.sql. Carries its own grants, at the
--     bottom.
--
--  WHY THIS EXISTS AT ALL
--
--  Supabase's free plan has no restorable backup. That is a survivable
--  property for a shop — a product description can be typed again — and it is
--  not one for a medical record: two years of a diabetic patient's history
--  cannot be reconstructed from memory.
--
--  Upgrading the plan is the real answer and docs/العيادة.md says so. This is
--  the second half of it, and it is not redundant with the first: a backup
--  nobody has ever held is a backup nobody has ever verified. A file the owner
--  downloads, opens and can read without this system running is a different
--  kind of safety from a checkbox in a dashboard.
--
--  DIRECTOR ONLY, AND AUDITED. This is a bulk read of every patient record in
--  the clinic — the single most sensitive operation the system can perform. It
--  refuses anyone else inside the function, and it writes down that it
--  happened before it hands anything over.
-- ============================================================================

create or replace function clinic.export_all()
returns jsonb
language plpgsql security definer set search_path = clinic, public as $$
declare v_out jsonb;
begin
  if not clinic.is_director() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;

  -- Written BEFORE the data is assembled, so an export that fails halfway or
  -- is cancelled mid-download still leaves the trace. The interesting question
  -- an audit log answers is "who asked", not "who succeeded".
  insert into clinic.audit_events (actor_id, action, entity, detail)
  values (auth.uid(), 'exported_everything', 'clinic',
          jsonb_build_object('patients',
            (select count(*) from clinic.patients)));

  select jsonb_build_object(
    'exported_at', now(),
    'schema_version', 1,

    'clinic',   (select to_jsonb(s) from clinic.settings s where s.id),

    -- No passwords here and none reachable: credentials live in auth.users,
    -- which this schema does not touch. Restoring this file recreates the
    -- records, not the logins.
    'staff',    coalesce((select jsonb_agg(to_jsonb(x)) from clinic.staff x), '[]'::jsonb),

    'patients', coalesce((select jsonb_agg(to_jsonb(x)) from clinic.patients x), '[]'::jsonb),
    'visits',   coalesce((select jsonb_agg(to_jsonb(x)) from clinic.visits x), '[]'::jsonb),
    'encounters',
                coalesce((select jsonb_agg(to_jsonb(x)) from clinic.encounters x), '[]'::jsonb),

    -- Prescriptions carry their lines inline rather than as a second top-level
    -- array. A backup is read by a human under pressure; a prescription whose
    -- drugs are somewhere else in the file is a prescription they have to
    -- reassemble by hand.
    'prescriptions', coalesce((
      select jsonb_agg(to_jsonb(r) || jsonb_build_object('items', coalesce((
               select jsonb_agg(to_jsonb(i) order by i.line_no)
                 from clinic.prescription_items i where i.rx_id = r.id), '[]'::jsonb)))
        from clinic.prescriptions r), '[]'::jsonb),

    'lab_requests', coalesce((
      select jsonb_agg(to_jsonb(q) || jsonb_build_object('items', coalesce((
               select jsonb_agg(to_jsonb(i) order by i.line_no)
                 from clinic.lab_request_items i where i.req_id = q.id), '[]'::jsonb)))
        from clinic.lab_requests q), '[]'::jsonb),

    'payments', coalesce((select jsonb_agg(to_jsonb(x)) from clinic.payments x), '[]'::jsonb),
    'attachments',
                coalesce((select jsonb_agg(to_jsonb(x)) from clinic.attachments x), '[]'::jsonb),
    'audit',    coalesce((select jsonb_agg(to_jsonb(x)) from clinic.audit_events x), '[]'::jsonb)
  ) into v_out;

  return v_out;
end $$;

-- ---------------------------------------------------------------------------
--  عدّاد سريع — قبل ما تنزّل، وبعد ما تنزّل
--
--  So the settings screen can say "٣٤٧ مريض و ١٢٠٤ روشتة" next to the button
--  and again after the file lands. A downloaded backup nobody checked the size
--  of is how an empty file gets filed away for a year.
-- ---------------------------------------------------------------------------
create or replace function clinic.export_counts()
returns jsonb
language sql stable security definer set search_path = clinic, public as $$
  select case when not clinic.is_director() then null else jsonb_build_object(
    'patients',      (select count(*) from clinic.patients),
    'encounters',    (select count(*) from clinic.encounters),
    'prescriptions', (select count(*) from clinic.prescriptions),
    'visits',        (select count(*) from clinic.visits),
    'last_export',   (select max(created_at) from clinic.audit_events
                       where action = 'exported_everything')
  ) end
$$;

-- ---------------------------------------------------------------- grants ---

revoke execute on function clinic.export_all()    from public, anon;
revoke execute on function clinic.export_counts() from public, anon;

grant execute on function clinic.export_all()    to authenticated;
grant execute on function clinic.export_counts() to authenticated;
