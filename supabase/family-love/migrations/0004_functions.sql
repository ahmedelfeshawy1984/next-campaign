-- ============================================================================
--  Family Love — منطق العمل (RPCs)
-- ============================================================================

-- ------------------------------------------------------------ الحساب/الحلقة -

-- بتتنادى بس من مسار السيرفر (service role) بعد نجاح التحقق من OTP — أول مرة
-- بتنشئ الحساب، الدائرة، وصف الاشتراك (تجربة مجانية) مع بعض.
create or replace function public.fl_upsert_parent_account(p_phone text, p_full_name text)
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

  insert into public.accounts (phone, full_name)
  values (v_phone, nullif(trim(coalesce(p_full_name, '')), ''))
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

revoke execute on function public.fl_upsert_parent_account(text, text) from public, anon, authenticated;

-- ------------------------------------------------------------------ الطفل --

create or replace function public.fl_create_child_profile(p_display_name text, p_avatar_url text default null)
returns public.child_profiles
language plpgsql security definer set search_path = public as $$
declare
  v_name text := nullif(trim(coalesce(p_display_name, '')), '');
  v_row  public.child_profiles;
begin
  if not public.fl_is_parent() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if v_name is null then
    raise exception 'NAME_REQUIRED' using errcode = 'P0001';
  end if;

  insert into public.child_profiles (family_circle_id, display_name, avatar_url)
  values (public.fl_my_circle(), v_name, p_avatar_url)
  returning * into v_row;

  return v_row;
end $$;

revoke execute on function public.fl_create_child_profile(text, text) from public, anon;
grant execute on function public.fl_create_child_profile(text, text) to authenticated;

-- كود من 8 حروف/أرقام، صلاحية ١٥ دقيقة. بيتاح للأب/الأم بس، ومحصور في أطفال
-- دائرته هو.
create or replace function public.fl_create_pairing_token(p_child_profile_id uuid)
returns public.pairing_tokens
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_row  public.pairing_tokens;
  v_code text;
begin
  if not public.fl_is_parent() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if (select family_circle_id from public.child_profiles where id = p_child_profile_id)
       is distinct from public.fl_my_circle() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;

  loop
    v_code := upper(substr(
      regexp_replace(encode(gen_random_bytes(6), 'base64'), '[^A-Za-z0-9]', '', 'g'), 1, 8));
    begin
      insert into public.pairing_tokens (child_profile_id, code, created_by, expires_at)
      values (p_child_profile_id, v_code, public.fl_my_account_id(), now() + interval '15 minutes')
      returning * into v_row;
      exit;
    exception when unique_violation then
      -- كود اتكرر بالصدفة، جرّب تاني بكود مختلف.
    end;
  end loop;

  return v_row;
end $$;

revoke execute on function public.fl_create_pairing_token(uuid) from public, anon;
grant execute on function public.fl_create_pairing_token(uuid) to authenticated;

-- الاستبدال الفعلي (redeem) بيحصل من مسار سيرفر بمفتاح service role — الدالة
-- دي مش متاحة لا لـ anon ولا authenticated لأن اللي بيستبدل الكود لسه معندوش
-- أي جلسة خالص وقت الاستبدال.
create or replace function public.fl_redeem_pairing_token(p_code text)
returns public.pairing_tokens
language plpgsql security definer set search_path = public as $$
declare
  v_row public.pairing_tokens;
begin
  select * into v_row from public.pairing_tokens
   where code = upper(trim(p_code))
     and redeemed_at is null
     and expires_at > now()
   for update;

  if v_row.id is null then
    raise exception 'CODE_INVALID_OR_EXPIRED' using errcode = 'P0001';
  end if;

  return v_row;
end $$;

revoke execute on function public.fl_redeem_pairing_token(text) from public, anon, authenticated;

create or replace function public.fl_mark_pairing_token_redeemed(p_token_id uuid, p_device_session_id uuid)
returns void
language sql security definer set search_path = public as $$
  update public.pairing_tokens
     set redeemed_at = now(), redeemed_device_session_id = p_device_session_id
   where id = p_token_id
$$;

revoke execute on function public.fl_mark_pairing_token_redeemed(uuid, uuid) from public, anon, authenticated;

-- --------------------------------------------------- المهام واللوحة اليومية -

-- بتتأكد إن المهمة فعلاً بتحصل النهاردة، وتنشئ صف task_occurrences لو مش
-- موجود (lazy creation — مفيش cron بيولّد صفوف الأيام مقدمًا).
create or replace function public.fl_get_or_create_today_occurrence(p_task_id uuid)
returns public.task_occurrences
language plpgsql security definer set search_path = public as $$
declare
  v_task public.tasks;
  v_occ  public.task_occurrences;
begin
  select * into v_task from public.tasks where id = p_task_id;
  if v_task.id is null then
    raise exception 'TASK_NOT_FOUND' using errcode = 'P0001';
  end if;
  if v_task.family_circle_id is distinct from public.fl_my_circle() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if current_date < v_task.starts_on or (v_task.ends_on is not null and current_date > v_task.ends_on) then
    raise exception 'OUT_OF_RANGE' using errcode = 'P0001';
  end if;
  if not public.fl_task_occurs_on(v_task.recurrence_rule, current_date) then
    raise exception 'NOT_TODAY' using errcode = 'P0001';
  end if;

  select * into v_occ from public.task_occurrences
   where task_id = p_task_id and occurrence_date = current_date;

  if v_occ.id is null then
    insert into public.task_occurrences (task_id, child_profile_id, occurrence_date)
    values (p_task_id, v_task.child_profile_id, current_date)
    returning * into v_occ;
  end if;

  return v_occ;
end $$;

revoke execute on function public.fl_get_or_create_today_occurrence(uuid) from public, anon;
grant execute on function public.fl_get_or_create_today_occurrence(uuid) to authenticated;

-- مسار الكتابة الوحيد لـ current_station_index. بتتأكد إن الجهاز اللي ضغط هو
-- فعلاً جهاز الطفل بتاع المحطة دي، وبتسجّل الحدث في station_events.
create or replace function public.fl_advance_station(p_occurrence_id uuid)
returns public.task_occurrences
language plpgsql security definer set search_path = public as $$
declare
  v_occ           public.task_occurrences;
  v_station_count int;
  v_next          int;
begin
  select * into v_occ from public.task_occurrences where id = p_occurrence_id;
  if v_occ.id is null then
    raise exception 'OCCURRENCE_NOT_FOUND' using errcode = 'P0001';
  end if;
  if v_occ.child_profile_id is distinct from public.fl_my_child_profile_id() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if v_occ.status = 'done' then
    return v_occ;
  end if;

  select count(*) into v_station_count from public.stations where task_id = v_occ.task_id;
  v_next := least(v_occ.current_station_index + 1, v_station_count);

  update public.task_occurrences
     set current_station_index = v_next,
         status = case when v_next >= v_station_count then 'done' else 'in_progress' end,
         updated_at = now()
   where id = p_occurrence_id
   returning * into v_occ;

  insert into public.station_events (occurrence_id, station_index, actor_device_session_id)
  values (p_occurrence_id, v_next, auth.uid());

  return v_occ;
end $$;

revoke execute on function public.fl_advance_station(uuid) from public, anon;
grant execute on function public.fl_advance_station(uuid) to authenticated;

-- لوحة اليوم: الأب/الأم لازم يمرروا p_child_profile_id، والطفل بيسيبها فاضية
-- (بتاخد جهازه هو). بترجع كل مهمة نشطة النهاردة مع محطاتها وتقدّمها الحالي،
-- وبتضمن وجود صف task_occurrences لكل مهمة (عشان الاشتراك في Realtime يبقى
-- مستقر من أول تحميل).
create or replace function public.fl_today_board(p_child_profile_id uuid default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_child_id uuid;
  v_task     record;
  v_result   jsonb;
begin
  if public.fl_is_parent() then
    if p_child_profile_id is null then
      raise exception 'CHILD_REQUIRED' using errcode = 'P0001';
    end if;
    v_child_id := p_child_profile_id;
    if (select family_circle_id from public.child_profiles where id = v_child_id)
         is distinct from public.fl_my_circle() then
      raise exception 'NOT_ALLOWED' using errcode = 'P0001';
    end if;
  else
    v_child_id := public.fl_my_child_profile_id();
  end if;

  for v_task in
    select * from public.tasks
     where child_profile_id = v_child_id
       and is_active
       and current_date >= starts_on
       and (ends_on is null or current_date <= ends_on)
       and public.fl_task_occurs_on(recurrence_rule, current_date)
  loop
    perform public.fl_get_or_create_today_occurrence(v_task.id);
  end loop;

  select coalesce(jsonb_agg(row), '[]'::jsonb) into v_result
  from (
    select
      tk.id as task_id,
      tk.title,
      occ.id as occurrence_id,
      occ.current_station_index,
      occ.status,
      (select jsonb_agg(
                jsonb_build_object('order_index', s.order_index, 'title', s.title, 'icon', s.icon)
                order by s.order_index)
         from public.stations s where s.task_id = tk.id) as stations
    from public.tasks tk
    join public.task_occurrences occ
      on occ.task_id = tk.id and occ.occurrence_date = current_date
    where tk.child_profile_id = v_child_id
    order by tk.created_at
  ) row;

  return v_result;
end $$;

revoke execute on function public.fl_today_board(uuid) from public, anon;
grant execute on function public.fl_today_board(uuid) to authenticated;

-- ------------------------------------------------------------- الإعلانات ---

create or replace function public.fl_active_ad(p_governorate text default null, p_city text default null)
returns public.ad_creatives
language sql stable security definer set search_path = public as $$
  select c.* from public.ad_creatives c
  join public.ad_targets t on t.creative_id = c.id
  where c.is_active
    and now() >= c.starts_at
    and (c.ends_at is null or now() <= c.ends_at)
    and (
      (t.scope = 'city'        and p_city is not null and t.city = p_city) or
      (t.scope = 'governorate' and p_governorate is not null and t.governorate = p_governorate) or
      (t.scope = 'all_egypt')
    )
  order by case t.scope when 'city' then 0 when 'governorate' then 1 else 2 end, random()
  limit 1
$$;

revoke execute on function public.fl_active_ad(text, text) from public, anon;
grant execute on function public.fl_active_ad(text, text) to authenticated;

-- ----------------------------------------------------------- الاشتراكات ----

create or replace function public.fl_my_entitlement()
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'status', s.status,
    'trial_ends_at', s.trial_ends_at,
    'current_period_end', s.current_period_end,
    'platform', s.platform
  )
  from public.subscriptions s
  where s.family_circle_id = public.fl_my_circle()
$$;

revoke execute on function public.fl_my_entitlement() from public, anon;
grant execute on function public.fl_my_entitlement() to authenticated;
