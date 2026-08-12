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
