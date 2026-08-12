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
