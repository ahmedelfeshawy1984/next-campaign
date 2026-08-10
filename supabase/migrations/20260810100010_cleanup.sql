-- ============================================================================
--  تنظيف الملفات اليتيمة والحسابات المجهولة
--
--  ⚠  Sorts AFTER 20260810100006_rls.sql. Carries its own grants.
--
--  Anonymous sign-in is what makes "upload your logo without creating an
--  account" possible, and the bill for it is a row in auth.users per visitor
--  who touches the uploader plus an object in storage for every file they
--  picked and then abandoned. Neither is a problem this week and both are a
--  problem next year.
--
--  The work is a FUNCTION first and a schedule second, on purpose: pg_cron has
--  to be enabled by hand in the Supabase dashboard, and a cleanup that only
--  exists as a cron job is a cleanup that silently never runs on a project
--  where nobody enabled it. This way the owner can also run one line in the SQL
--  editor.
-- ============================================================================

create or replace function public.cleanup_orphan_uploads(p_days int default 7)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_files int := 0;
  v_objects int := 0;
  v_users int := 0;
begin
  -- TWO GATES, and both are needed.
  --
  -- The grant below is what stops anon: Postgres gives EXECUTE on every new
  -- function to PUBLIC, so `revoke ... from anon` on its own does NOTHING —
  -- anon still holds it through PUBLIC. That is why the revoke at the bottom
  -- names public explicitly, and it is the reason this check exists too.
  --
  -- This check is what stops a signed-in non-manager. It deliberately allows a
  -- NULL uid through, because that is pg_cron running as the database owner,
  -- who has no JWT and never will. anon also has a null uid — which is exactly
  -- why the grant, not this check, is what keeps anon out.
  if auth.uid() is not null and not public.is_manager() then
    raise exception 'NOT_AUTHORISED';
  end if;

  -- Files nobody attached to an order. The order's own assets are never
  -- touched: they are evidence of what was agreed, and they outlive the upload
  -- log they came from.
  with doomed as (
    delete from public.customer_uploads u
     where u.created_at < now() - make_interval(days => p_days)
       and not exists (
         select 1 from public.order_line_assets a where a.upload_id = u.id)
    returning u.storage_path
  ), removed as (
    delete from storage.objects o
     using doomed d
     where o.bucket_id = 'customer-artwork' and o.name = d.storage_path
    returning o.name
  )
  -- Counted separately on purpose: the log row and the stored object can go out
  -- of step (an upload interrupted between the two writes), and a single number
  -- would hide that rather than show it.
  select (select count(*) from doomed), (select count(*) from removed)
    into v_files, v_objects;

  -- Anonymous profiles that never became an order. A profile with a phone was
  -- a real sign-up and is left alone.
  delete from public.profiles p
   where p.role = 'customer'
     and p.phone is null
     and p.created_at < now() - make_interval(days => p_days)
     and not exists (select 1 from public.customer_uploads u where u.owner_id = p.id)
     and not exists (select 1 from public.order_line_assets a where a.uploaded_by = p.id);
  get diagnostics v_users = row_count;

  return jsonb_build_object(
    'uploads_removed', v_files,
    'objects_removed', v_objects,
    'profiles_removed', v_users);
end $$;

-- Schedule it if the extension is available; say nothing if it is not, and
-- leave the function callable by hand.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    begin
      create extension if not exists pg_cron;
      perform cron.unschedule('nc-cleanup-uploads')
        where exists (select 1 from cron.job where jobname = 'nc-cleanup-uploads');
      perform cron.schedule(
        'nc-cleanup-uploads', '30 3 * * *',
        $cmd$select public.cleanup_orphan_uploads(7)$cmd$);
    exception when others then
      raise notice 'pg_cron present but not schedulable here — run cleanup_orphan_uploads() manually';
    end;
  else
    raise notice 'pg_cron not available — run select public.cleanup_orphan_uploads(); from time to time';
  end if;
end $$;

-- ⚠  FROM PUBLIC, not just from anon.
--
-- Postgres grants EXECUTE on every new function to PUBLIC. Revoking from anon
-- alone leaves the PUBLIC grant intact and anon keeps the privilege — which is
-- how a SECURITY DEFINER function that DELETES rows ended up callable by any
-- visitor until the harness caught it. Anywhere a function's protection is the
-- grant rather than a check inside it, the revoke must name public.
revoke execute on function public.cleanup_orphan_uploads(int) from public, anon;
grant execute on function public.cleanup_orphan_uploads(int) to authenticated;
