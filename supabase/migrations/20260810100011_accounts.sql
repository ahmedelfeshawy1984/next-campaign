-- ============================================================================
--  الحسابات — دخول الإدارة
--
--  ⚠  Sorts AFTER 20260810100006_rls.sql. Carries its own revokes and grants.
--
--  Only staff sign in. Customers browse, configure, upload artwork and file
--  orders with no account at all — that is the whole design, and this file
--  exists to give the shop's own people a door.
--
--  Ported from the sibling project, including three traps that cost real time
--  there and are commented where they bite.
-- ============================================================================

-- The phone → synthetic email bridge. Supabase's real phone auth bills per SMS
-- through a third party, and a shop with four staff does not need it: the
-- number is the username, the address is derived, and nobody ever reads that
-- mailbox.
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

-- Nobody may call the private body directly — it takes the ROLE as an
-- argument, so a grant here would be a way for a visitor to mint a manager.
revoke execute on function
  public.create_account(text, text, text, public.user_role)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
--  The manager's door.
-- ---------------------------------------------------------------------------
create or replace function public.admin_create_user(
  p_phone     text,
  p_full_name text,
  p_role      public.user_role,
  p_password  text
) returns uuid
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_manager() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  return public.create_account(p_phone, p_full_name, p_password, p_role);
end $$;

create or replace function public.admin_set_password(p_id uuid, p_password text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  -- Either a manager resetting somebody's password, or a person changing their
  -- own. Both are legitimate; nothing else is.
  if not (public.is_manager() or p_id = auth.uid()) then
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

create or replace function public.admin_set_active(p_id uuid, p_active boolean)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_manager() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  -- Switching yourself off locks the shop out of its own admin panel.
  if p_id = auth.uid() then
    raise exception 'CANNOT_DISABLE_SELF' using errcode = 'P0001';
  end if;
  if not p_active and (
       select count(*) from public.profiles
        where role = 'manager' and is_active and id <> p_id
     ) = 0 then
    raise exception 'LAST_MANAGER' using errcode = 'P0001';
  end if;

  update public.profiles set is_active = p_active where id = p_id;
end $$;

create or replace function public.admin_staff()
returns table (id uuid, full_name text, phone text, role public.user_role,
               is_active boolean, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select p.id, p.full_name, p.phone, p.role, p.is_active, p.created_at
    from public.profiles p
   where public.is_manager() and p.phone is not null
   order by p.created_at
$$;

-- ---------------------------------------------------------------------------
--  Deleting a product.
--
--  Refused once a customer has ordered it. The order line snapshots the name
--  and the price, so the paperwork survives — but the row is still the only
--  link back to what was actually sold, and "how many of these have we done?"
--  stops being answerable the moment it goes.
--
--  Unpublishing is what the owner actually wants in that case, and the panel
--  says so.
-- ---------------------------------------------------------------------------
create or replace function public.admin_delete_product(p_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_manager() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.order_request_lines where product_id = p_id) then
    raise exception 'HAS_HISTORY' using errcode = 'P0001';
  end if;
  delete from public.products where id = p_id;
end $$;

-- ---------------------------------------------------------------------------
--  A signed URL is the only way to read customer artwork: the bucket is
--  private, and it stays private. This wraps the check so the panel does not
--  have to hold a service key to show the owner a logo.
-- ---------------------------------------------------------------------------
create or replace function public.admin_dashboard()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.is_manager() then null else jsonb_build_object(
    'new',            (select count(*) from public.order_requests where status = 'new'),
    'awaiting_proof', (select count(*) from public.order_requests where status = 'artwork_review'),
    'in_production',  (select count(*) from public.order_requests
                        where status in ('artwork_approved','in_production')),
    'urgent',         (select count(*) from public.order_requests
                        where needed_by is not null
                          and needed_by <= current_date + 7
                          and status not in ('delivered','cancelled')),
    'mismatch',       (select count(*) from public.order_requests where price_mismatch),
    'drafts',         (select count(*) from public.products where not is_published),
    'no_cover',       (select count(*) from public.products
                        where is_published and cover_url is null)
  ) end
$$;

-- ---------------------------------------------------------------- grants ---

revoke execute on function public.email_for_phone(text)                              from public, anon;
revoke execute on function public.fix_auth_user_tokens(uuid)                         from public, anon, authenticated;
revoke execute on function public.admin_create_user(text, text, public.user_role, text) from public, anon;
revoke execute on function public.admin_set_password(uuid, text)                     from public, anon;
revoke execute on function public.admin_set_active(uuid, boolean)                    from public, anon;
revoke execute on function public.admin_delete_product(uuid)                         from public, anon;
revoke execute on function public.admin_staff()                                      from public, anon;
revoke execute on function public.admin_dashboard()                                  from public, anon;

-- The login screen turns a phone into the synthetic address before calling
-- signInWithPassword, so anon needs this one.
grant execute on function public.email_for_phone(text) to anon, authenticated;

grant execute on function public.admin_create_user(text, text, public.user_role, text) to authenticated;
grant execute on function public.admin_set_password(uuid, text)  to authenticated;
grant execute on function public.admin_set_active(uuid, boolean) to authenticated;
grant execute on function public.admin_delete_product(uuid)      to authenticated;
grant execute on function public.admin_staff()                   to authenticated;
grant execute on function public.admin_dashboard()               to authenticated;

-- ============================================================================
--  أول حساب مدير
--
--  الموبايل 01000000000 وكلمة السر تحت.
--  ⚠  غيّر كلمة السر أول ما تدخل — الملف ده موجود في المستودع، فأي حد يقراه
--     يعرف كلمة السر دي.
--
--  Re-runnable: a second run finds a manager already there and does nothing.
-- ============================================================================
do $$
begin
  if not exists (select 1 from public.profiles where role = 'manager') then
    perform public.create_account('01000000000', 'المدير', 'campaign2026', 'manager');
  end if;
end $$;
