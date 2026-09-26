-- ============================================================================
--  Family Love — إدارة الأجهزة (شاشة الإعدادات)
--
--  device_sessions_select_self بتسمح لكل جهاز يشوف نفسه بس (مقصودة كده في
--  0003_auth_rls.sql). عشان الأب/الأم يقدر يشوف كل أجهزة دائرته ويسحب واحد
--  ضاع أو الطفل مبقاش محتاجه، لازم دالة SECURITY DEFINER منفصلة — بتتأكد
--  الجهاز فعلاً تابع لدائرة المستخدم قبل ما ترجّع أو تعدّل أي حاجة.
-- ============================================================================

create or replace function public.fl_my_circle_devices()
returns table (
  id uuid,
  kind public.device_kind,
  label text,
  created_at timestamptz,
  last_seen_at timestamptz,
  revoked_at timestamptz
)
language plpgsql security definer set search_path = public as $$
begin
  if not public.fl_is_parent() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;

  return query
    select
      ds.id,
      ds.kind,
      coalesce(cp.display_name, a.full_name, a.phone, 'جهاز') as label,
      ds.created_at,
      ds.last_seen_at,
      ds.revoked_at
    from public.device_sessions ds
    left join public.child_profiles cp on cp.id = ds.child_profile_id
    left join public.accounts a on a.id = ds.account_id
    where
      (ds.kind = 'parent' and exists (
        select 1 from public.family_members fm
         where fm.account_id = ds.account_id and fm.family_circle_id = public.fl_my_circle()
      ))
      or
      (ds.kind = 'child' and exists (
        select 1 from public.child_profiles cp2
         where cp2.id = ds.child_profile_id and cp2.family_circle_id = public.fl_my_circle()
      ))
    order by ds.created_at;
end $$;

revoke execute on function public.fl_my_circle_devices() from public, anon;
grant execute on function public.fl_my_circle_devices() to authenticated;

-- ---------------------------------------------------------------------------

create or replace function public.fl_revoke_device(p_device_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_belongs_to_my_circle boolean;
begin
  if not public.fl_is_parent() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;

  select exists (
    select 1 from public.device_sessions ds
     where ds.id = p_device_id
       and (
         (ds.kind = 'parent' and exists (
           select 1 from public.family_members fm
            where fm.account_id = ds.account_id and fm.family_circle_id = public.fl_my_circle()
         ))
         or
         (ds.kind = 'child' and exists (
           select 1 from public.child_profiles cp
            where cp.id = ds.child_profile_id and cp.family_circle_id = public.fl_my_circle()
         ))
       )
  ) into v_belongs_to_my_circle;

  if not v_belongs_to_my_circle then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;

  -- سحب الجهاز فوري وكافي لوحده: كل دوال fl_my_*() بتفلتر revoked_at is null،
  -- فـ fl_my_circle() بترجع null للجهاز ده فورًا وأي RLS بيرفضه من غير ما
  -- نحتاج نلغي الـ JWT نفسه (هو أصلاً قصير العمر - 15 دقيقة).
  update public.device_sessions set revoked_at = now() where id = p_device_id;
end $$;

revoke execute on function public.fl_revoke_device(uuid) from public, anon;
grant execute on function public.fl_revoke_device(uuid) to authenticated;
