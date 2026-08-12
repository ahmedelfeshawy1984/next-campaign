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
