-- ============================================================================
--  العيادة — الترويسة وكتالوج الأدوية بالجملة
--
--  ⚠  Sorts AFTER 20260810100006_rls.sql. Carries its own grants, at the
--     bottom.
-- ============================================================================

-- ---------------------------------------------------------------------------
--  لوجو العيادة — جوّه الإعدادات، مش في bucket
--
--  A data: URI in a column, and that is a deliberate choice against the obvious
--  one.
--
--  A logo in Supabase Storage is an image the browser fetches over the network.
--  The prescription is the one screen in this system built to work when there
--  is no network — so the first time the clinic's internet drops, every sheet
--  prints with a blank space where the letterhead should be, and nothing says
--  why. Storing the bytes with the settings means the logo travels onto the
--  device with everything else and prints regardless.
--
--  The cost is a fat column, and it is capped. The browser resizes to 600px and
--  compresses before this is ever reached (see web/lib/clinic/logo.ts); the
--  check is the backstop for a five-megabyte photograph pasted in by hand,
--  which would otherwise be downloaded by every device on every settings read.
-- ---------------------------------------------------------------------------
alter table clinic.settings
  add column if not exists logo_url text;

do $$ begin
  alter table clinic.settings
    add constraint clinic_logo_size check (logo_url is null or length(logo_url) <= 400000);
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
--  مرفقات المرضى — الـ bucket اللي clinic.attachments بيشاور عليه
--
--  PRIVATE, and read through a signed URL. A scan of a patient's blood test is
--  not a shop window. The table has referenced this bucket since it was
--  written; creating it now closes a gap rather than adding a feature.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('clinic-files', 'clinic-files', false, 20971520, null)
on conflict (id) do nothing;

drop policy if exists clinic_files_read on storage.objects;
create policy clinic_files_read on storage.objects
  for select to authenticated
  using (bucket_id = 'clinic-files' and clinic.is_clinician());

drop policy if exists clinic_files_write on storage.objects;
create policy clinic_files_write on storage.objects
  for all to authenticated
  using (bucket_id = 'clinic-files' and clinic.is_clinician())
  with check (bucket_id = 'clinic-files' and clinic.is_clinician());

-- ---------------------------------------------------------------------------
--  استيراد أدوية بالجملة
--
--  The catalogue that ships is a starting point — a hundred common brands. A
--  clinic's own list is better than it by a wide margin, and it already exists
--  somewhere: an Excel sheet, the old system, a pharmacy's price list. This is
--  the door for it.
--
--  SET-BASED, not a loop, and that is not a micro-optimisation. Every write to
--  clinic.drugs fires the statement-level trigger that bumps the catalogue
--  version; a loop over three thousand rows would fire it three thousand times
--  and rewrite the settings row just as often. One statement, one bump.
--
--  DISTINCT ON is load-bearing too: a pasted list with the same drug twice
--  makes Postgres raise "ON CONFLICT DO UPDATE command cannot affect row a
--  second time", which is a real error with an unreadable message for someone
--  who just pasted a spreadsheet.
-- ---------------------------------------------------------------------------
create or replace function clinic.import_drugs(p_rows jsonb)
returns jsonb
language plpgsql security definer set search_path = clinic, public as $$
declare v_out jsonb; v_seen int; v_valid int;
begin
  if not clinic.is_director() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'BAD_PAYLOAD' using errcode = 'P0001';
  end if;
  -- A ceiling, so a paste that was meant for a different system cannot lock
  -- the catalogue for a minute. Bigger lists arrive in batches.
  if jsonb_array_length(p_rows) > 5000 then
    raise exception 'IMPORT_TOO_BIG' using errcode = 'P0001';
  end if;

  with parsed as (
    select
      nullif(trim(coalesce(x.trade_name, '')), '')       as trade_name,
      coalesce(trim(coalesce(x.trade_name_ar, '')), '')  as trade_name_ar,
      nullif(trim(coalesce(x.generic_ar, '')), '')       as generic_ar,
      nullif(trim(coalesce(x.generic_en, '')), '')       as generic_en,
      coalesce(trim(coalesce(x.form_ar, '')), '')        as form_ar,
      coalesce(trim(coalesce(x.strength, '')), '')       as strength
    from jsonb_to_recordset(p_rows) as x(
      trade_name text, trade_name_ar text, generic_ar text,
      generic_en text, form_ar text, strength text
    )
  ),
  valid as (
    select distinct on (trade_name, strength, form_ar) *
      from parsed where trade_name is not null
     order by trade_name, strength, form_ar
  ),
  done as (
    insert into clinic.drugs
      (trade_name, trade_name_ar, generic_ar, generic_en, form_ar, strength, is_active)
    select trade_name, trade_name_ar, generic_ar, generic_en, form_ar, strength, true
      from valid
    on conflict (trade_name, strength, form_ar) do update set
      -- An import ADDS to what is there; it does not blank a name somebody
      -- typed in by hand because this particular sheet had that column empty.
      trade_name_ar = case when excluded.trade_name_ar <> ''
                           then excluded.trade_name_ar else clinic.drugs.trade_name_ar end,
      generic_ar    = coalesce(excluded.generic_ar, clinic.drugs.generic_ar),
      generic_en    = coalesce(excluded.generic_en, clinic.drugs.generic_en),
      is_active     = true
    returning (xmax = 0) as inserted
  )
  select jsonb_build_object(
    'added',   count(*) filter (where inserted),
    'updated', count(*) filter (where not inserted)
  ) into v_out from done;

  select count(*) into v_seen  from jsonb_array_elements(p_rows);
  select count(*) into v_valid from (
    select distinct on (trade_name, strength, form_ar) 1 as k from (
      select nullif(trim(coalesce(x.trade_name,'')),'') as trade_name,
             coalesce(trim(coalesce(x.strength,'')),'') as strength,
             coalesce(trim(coalesce(x.form_ar,'')),'')  as form_ar
        from jsonb_to_recordset(p_rows) as x(trade_name text, strength text, form_ar text)
    ) q where trade_name is not null
      order by trade_name, strength, form_ar
  ) d;

  insert into clinic.audit_events (actor_id, action, entity, detail)
  values (auth.uid(), 'imported_drugs', 'drugs', v_out || jsonb_build_object('rows', v_seen));

  -- `skipped` is rows with no trade name plus duplicates within the paste
  -- itself. Reported rather than swallowed: a person who pastes 300 lines and
  -- is told "added 240" needs to know where the other 60 went.
  return v_out || jsonb_build_object('skipped', v_seen - v_valid, 'rows', v_seen);
end $$;

-- ---------------------------------------------------------------------------
--  شاشة الأدوية — بحث من السيرفر
--
--  The picker searches the copy on the device. This is for the MANAGEMENT
--  screen, which has to show inactive drugs too — they are exactly what the
--  device does not keep.
-- ---------------------------------------------------------------------------
create or replace function clinic.list_drugs(p_term text default null, p_limit int default 100)
returns table (
  id uuid, trade_name text, trade_name_ar text, generic_ar text, generic_en text,
  form_ar text, strength text, is_active boolean, uses int
)
language sql stable security definer set search_path = clinic, public as $$
  select d.id, d.trade_name, d.trade_name_ar, d.generic_ar, d.generic_en,
         d.form_ar, d.strength, d.is_active,
         coalesce((select sum(u.uses)::int from clinic.drug_usage u where u.drug_id = d.id), 0)
    from clinic.drugs d
   where clinic.is_staff()
     and (nullif(trim(coalesce(p_term, '')), '') is null
          or d.name_key like '%' || public.fold_arabic(trim(p_term)) || '%')
   order by d.is_active desc, d.trade_name
   limit greatest(1, least(coalesce(p_limit, 100), 500))
$$;

-- ---------------------------------------------------------------- grants ---

revoke execute on function clinic.import_drugs(jsonb)      from public, anon;
revoke execute on function clinic.list_drugs(text, int)    from public, anon;

grant execute on function clinic.import_drugs(jsonb)   to authenticated;
grant execute on function clinic.list_drugs(text, int) to authenticated;
