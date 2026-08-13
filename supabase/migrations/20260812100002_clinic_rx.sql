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
