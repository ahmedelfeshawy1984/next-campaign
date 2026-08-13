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
