-- ============================================================================
--  دوال مساعدة للصلاحيات والتطبيع
--
--  Every predicate used inside an RLS policy lives here, as SECURITY DEFINER
--  with a pinned search_path. Two reasons, both learned the hard way in the
--  sibling projects:
--
--    * A policy ON profiles that reads FROM profiles recurses forever. A
--      definer function is evaluated outside RLS and breaks the loop.
--    * An unpinned search_path lets anyone who can create a schema shadow
--      `profiles` with their own table and answer `is_manager()` themselves.
-- ============================================================================

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
