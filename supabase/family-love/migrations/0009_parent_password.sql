-- ============================================================================
--  استبدال تسجيل الدخول بكود OTP بـ رقم موبايل + باسورد
--
--  بعد تجربة فعلية، طلب صاحب المنتج نرجع لباسورد عادي للأب/الأم بدل كود
--  الإرسال (OTP) — أسرع للتنفيذ (من غير الحاجة لفتح حساب Twilio دلوقتي)
--  ومفهوم أكتر للمستخدم وقت الاختبار. الطفل يفضل بلا أي باسورد (كود ربط بس)
--  زي ما كان — القرار ده خاص بحسابات الأهل بس.
-- ============================================================================

alter table public.accounts add column password_hash text;

-- منح صلاحية على الجدول كله (زي `grant select on accounts to authenticated`
-- في 0003) بتغطي أي عمود جديد بيتضاف تلقائيًا — مفيش طريقة نستثني عمود واحد
-- بـ revoke بسيط فوق منحة على مستوى الجدول. الحل: نسحب منحة الجدول ونديها
-- تاني عمود عمود، ما عدا password_hash — لو أي كود قدّامي عمل select('*') على
-- accounts بجلسة أب/أم حقيقية، الهاش (حتى المُجزّأ) منعرضش في الاستجابة.
revoke select on public.accounts from authenticated;
grant select (id, phone, full_name, is_platform_admin, created_at) on public.accounts to authenticated;

-- لازم نمسح النسخة القديمة (بارامترين) قبل ما نضيف بارامتر تالت باختيار
-- افتراضي — وإلا Postgres هيشوف الاتنين "مرشحين" لأي نداء بـ٢ بارامتر
-- ويرفض ينفذ (ambiguous function call).
drop function if exists public.fl_upsert_parent_account(text, text);

create or replace function public.fl_upsert_parent_account(
  p_phone text, p_full_name text, p_password_hash text default null
)
returns public.accounts
language plpgsql security definer set search_path = public as $$
declare
  v_phone     text := public.normalize_phone(p_phone);
  v_row       public.accounts;
  v_circle_id uuid;
begin
  if v_phone is null or not public.is_eg_mobile(v_phone) then
    raise exception 'BAD_PHONE' using errcode = 'P0001';
  end if;

  insert into public.accounts (phone, full_name, password_hash)
  values (v_phone, nullif(trim(coalesce(p_full_name, '')), ''), p_password_hash)
  on conflict (phone) do update
    set full_name = coalesce(excluded.full_name, public.accounts.full_name)
  returning * into v_row;

  if not exists (select 1 from public.family_members where account_id = v_row.id) then
    insert into public.family_circles (owner_account_id) values (v_row.id)
    returning id into v_circle_id;

    insert into public.family_members (family_circle_id, account_id, is_owner)
    values (v_circle_id, v_row.id, true);

    insert into public.subscriptions (family_circle_id, trial_ends_at)
    select v_circle_id, now() + (select trial_days from public.family_love_settings) * interval '1 day';
  end if;

  return v_row;
end $$;

revoke execute on function public.fl_upsert_parent_account(text, text, text) from public, anon, authenticated;

drop function if exists public.fl_redeem_member_invite(text, text, text);

create or replace function public.fl_redeem_member_invite(
  p_code text, p_phone text, p_full_name text, p_password_hash text default null
)
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

  insert into public.accounts (phone, full_name, password_hash)
  values (v_phone, nullif(trim(coalesce(p_full_name, '')), ''), p_password_hash)
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

revoke execute on function public.fl_redeem_member_invite(text, text, text, text) from public, anon, authenticated;
