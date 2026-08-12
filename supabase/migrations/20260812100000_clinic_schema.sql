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
