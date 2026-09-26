-- ============================================================================
--  Family Love — دعوة فرد عيلة (زوج/زوجة، جدة، إلخ)
--
--  زي كود ربط الطفل بالظبط في الشكل، لكن بيربط "حساب بالغ" بالدائرة الموجودة
--  بدل ما يعمل دائرة جديدة — وده اللي fl_upsert_parent_account (تسجيل الدخول
--  العادي) بيعمله لأي رقم جديد، فمحتاجين مسار منفصل (fl_redeem_member_invite)
--  عشان الزوج/الزوجة المدعوين ينضموا لنفس دائرة اللي دعاهم، مش يبقى كل واحد
--  بدائرة لوحده.
-- ============================================================================

create table public.member_invites (
  id                     uuid primary key default gen_random_uuid(),
  family_circle_id       uuid not null references public.family_circles(id) on delete cascade,
  relation_type          public.relation_type not null,
  code                   text not null unique,
  created_by             uuid not null references public.accounts(id),
  expires_at             timestamptz not null,
  redeemed_at            timestamptz,
  redeemed_account_id    uuid references public.accounts(id),
  created_at             timestamptz not null default now()
);

alter table public.member_invites enable row level security;
revoke all on public.member_invites from anon;

create policy member_invites_select on public.member_invites
  for select using (public.fl_is_parent() and family_circle_id = public.fl_my_circle());
grant select on public.member_invites to authenticated;

-- ---------------------------------------------------------------------------

create or replace function public.fl_create_member_invite(p_relation_type public.relation_type)
returns public.member_invites
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_row  public.member_invites;
  v_code text;
begin
  if not public.fl_is_parent() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;

  loop
    v_code := upper(substr(
      regexp_replace(encode(gen_random_bytes(6), 'base64'), '[^A-Za-z0-9]', '', 'g'), 1, 8));
    begin
      insert into public.member_invites (family_circle_id, relation_type, code, created_by, expires_at)
      values (public.fl_my_circle(), p_relation_type, v_code, public.fl_my_account_id(), now() + interval '24 hours')
      returning * into v_row;
      exit;
    exception when unique_violation then
      -- كود اتكرر بالصدفة، جرّب تاني.
    end;
  end loop;

  return v_row;
end $$;

revoke execute on function public.fl_create_member_invite(public.relation_type) from public, anon;
grant execute on function public.fl_create_member_invite(public.relation_type) to authenticated;

-- بتتنادى بس من مسار سيرفر (service role) بعد التحقق من OTP بتاع الشخص
-- المدعو — نفس مبدأ fl_upsert_parent_account، لكن بتضم لدائرة موجودة بدل ما
-- تعمل واحدة جديدة.
create or replace function public.fl_redeem_member_invite(p_code text, p_phone text, p_full_name text)
returns public.family_members
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_invite  public.member_invites;
  v_phone   text := public.normalize_phone(p_phone);
  v_account public.accounts;
  v_member  public.family_members;
begin
  if v_phone is null or not public.is_eg_mobile(v_phone) then
    raise exception 'BAD_PHONE' using errcode = 'P0001';
  end if;

  select * into v_invite from public.member_invites
   where code = upper(trim(p_code)) and redeemed_at is null and expires_at > now()
   for update;
  if v_invite.id is null then
    raise exception 'CODE_INVALID_OR_EXPIRED' using errcode = 'P0001';
  end if;

  insert into public.accounts (phone, full_name)
  values (v_phone, nullif(trim(coalesce(p_full_name, '')), ''))
  on conflict (phone) do update
    set full_name = coalesce(excluded.full_name, public.accounts.full_name)
  returning * into v_account;

  insert into public.family_members (family_circle_id, account_id, relation_type)
  values (v_invite.family_circle_id, v_account.id, v_invite.relation_type)
  on conflict (family_circle_id, account_id) do update
    set relation_type = excluded.relation_type
  returning * into v_member;

  update public.member_invites
     set redeemed_at = now(), redeemed_account_id = v_account.id
   where id = v_invite.id;

  return v_member;
end $$;

revoke execute on function public.fl_redeem_member_invite(text, text, text) from public, anon, authenticated;
