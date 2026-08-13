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
