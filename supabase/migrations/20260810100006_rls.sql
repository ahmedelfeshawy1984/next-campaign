-- ============================================================================
--  RLS والصلاحيات
--
--  ⚠  THIS FILE SORTS AT INDEX 6 AND REVOKES EXECUTE ON ALL FUNCTIONS FROM
--     anon. Every migration added later MUST sort after it and MUST carry its
--     own grants. A migration numbered before it creates a function whose
--     grant is immediately revoked — and on an already-installed database this
--     file is not re-run, so the fault surfaces only on a fresh install months
--     later, in front of whoever is setting the system up for the first time.
--
--  The one deliberate departure from "anon gets nothing" is anonymous READ of
--  the catalogue. This is a shop window, and a shop window nobody can look into
--  before signing up is a shop window nobody looks into. Everything granted
--  below is what a passer-by would see through the glass anyway — and every
--  price on it is a price we print on the page.
--
--  Writes stay manager-only, everywhere, without exception.
-- ============================================================================

alter table public.profiles               enable row level security;
alter table public.categories             enable row level security;
alter table public.occasions              enable row level security;
alter table public.products               enable row level security;
alter table public.product_slug_aliases   enable row level security;
alter table public.product_option_groups  enable row level security;
alter table public.product_option_items   enable row level security;
alter table public.product_images         enable row level security;
alter table public.product_occasions      enable row level security;
alter table public.product_private        enable row level security;
alter table public.product_price_tiers    enable row level security;
alter table public.print_methods          enable row level security;
alter table public.print_positions        enable row level security;
alter table public.product_print_methods  enable row level security;
alter table public.position_print_methods enable row level security;
alter table public.fonts                  enable row level security;
alter table public.spec_defs              enable row level security;
alter table public.spec_options           enable row level security;
alter table public.spec_def_categories    enable row level security;
alter table public.site_settings          enable row level security;

-- Start from nothing…
revoke all on all tables in schema public from anon;

-- …then hand back SELECT on the shop window, table by table, BY NAME.
-- The list is explicit on purpose: `grant select on all tables in schema
-- public` would silently enrol every table added next year — including
-- order_requests, which carries customer phone numbers, and product_private,
-- which carries cost prices.
grant select on
  public.categories,
  public.occasions,
  public.products,
  public.product_slug_aliases,
  public.product_option_groups,
  public.product_option_items,
  public.product_images,
  public.product_occasions,
  public.product_price_tiers,
  public.print_methods,
  public.print_positions,
  public.product_print_methods,
  public.position_print_methods,
  public.fonts,
  public.spec_defs,
  public.spec_options,
  public.spec_def_categories,
  public.site_settings
to anon, authenticated;

-- Belt and braces: no future `alter default privileges` hands anon a pen.
revoke insert, update, delete, truncate on all tables in schema public from anon;

-- ---------------------------------------------------------------------------
--  Is this product on the shop floor? Definer, so the child-row policies below
--  can ask without recursing through products' own policy, and so the answer
--  is the same one the products policy gives.
-- ---------------------------------------------------------------------------
create or replace function public.product_visible(p_product uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.products
     where id = p_product and (is_published or public.is_manager())
  )
$$;

-- ------------------------------------------------------------- profiles ----

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_manager());

-- Escalation is blocked at the column level, not by a policy that could be
-- read as "the row is mine so the role is mine".
revoke update on public.profiles from authenticated;
grant update (full_name) on public.profiles to authenticated;

drop policy if exists profiles_self_update on public.profiles;
create policy profiles_self_update on public.profiles
  for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- ------------------------------------------------------------- products ----

drop policy if exists products_read on public.products;
create policy products_read on public.products
  for select to anon, authenticated
  using (is_published or public.is_manager());   -- drafts stay backstage

drop policy if exists products_write on public.products;
create policy products_write on public.products
  for all to authenticated
  using (public.is_manager()) with check (public.is_manager());

-- --------------------------------------------- reference tables (public) ----

do $$
declare t text;
begin
  foreach t in array array[
    'categories','occasions','print_methods','fonts',
    'spec_defs','spec_options','spec_def_categories','site_settings'
  ] loop
    execute format('drop policy if exists %I_read on public.%I', t, t);
    execute format(
      'create policy %I_read on public.%I for select to anon, authenticated using (true)', t, t);
    execute format('drop policy if exists %I_write on public.%I', t, t);
    execute format(
      'create policy %I_write on public.%I for all to authenticated
         using (public.is_manager()) with check (public.is_manager())', t, t);
  end loop;
end $$;

-- ------------------------------------ child rows follow their parent row ----

do $$
declare t text;
begin
  foreach t in array array[
    'product_slug_aliases','product_option_groups','product_images',
    'product_occasions','product_price_tiers','print_positions',
    'product_print_methods'
  ] loop
    execute format('drop policy if exists %I_read on public.%I', t, t);
    execute format(
      'create policy %I_read on public.%I for select to anon, authenticated
         using (public.product_visible(product_id))', t, t);
    execute format('drop policy if exists %I_write on public.%I', t, t);
    execute format(
      'create policy %I_write on public.%I for all to authenticated
         using (public.is_manager()) with check (public.is_manager())', t, t);
  end loop;
end $$;

-- Grandchildren: reachable only through their parent.

drop policy if exists product_option_items_read on public.product_option_items;
create policy product_option_items_read on public.product_option_items
  for select to anon, authenticated
  using (exists (
    select 1 from public.product_option_groups g
     where g.id = group_id and public.product_visible(g.product_id)
  ));

drop policy if exists product_option_items_write on public.product_option_items;
create policy product_option_items_write on public.product_option_items
  for all to authenticated
  using (public.is_manager()) with check (public.is_manager());

drop policy if exists position_print_methods_read on public.position_print_methods;
create policy position_print_methods_read on public.position_print_methods
  for select to anon, authenticated
  using (exists (
    select 1 from public.print_positions p
     where p.id = position_id and public.product_visible(p.product_id)
  ));

drop policy if exists position_print_methods_write on public.position_print_methods;
create policy position_print_methods_write on public.position_print_methods
  for all to authenticated
  using (public.is_manager()) with check (public.is_manager());

-- -------------------------------------------------------------- private ----

-- No anon grant above, and no anon policy here. Managers only, both ways.
drop policy if exists product_private_all on public.product_private;
create policy product_private_all on public.product_private
  for all to authenticated
  using (public.is_manager()) with check (public.is_manager());

-- ------------------------------------------------------------ functions ----

-- ⚠  FROM public, NOT just from anon.
--
-- Postgres grants EXECUTE on every new function to PUBLIC. `revoke ... from
-- anon` alone leaves that intact and anon keeps the privilege through PUBLIC —
-- so the revoke does nothing, silently, and every function in the schema stays
-- callable by any visitor. This bit us for real: a SECURITY DEFINER cleanup
-- function that DELETES rows was reachable by anon until the harness caught it.
--
-- Every migration after this one must do the same for its own functions:
-- revoke from public by name, then grant by name. See the bottom of
-- 20260810100008_quote.sql and 20260810100009_orders.sql.
revoke execute on all functions in schema public from public, anon;

-- Granted BY NAME, and the list is longer than it looks it should be because
-- REVOKING FROM PUBLIC ALSO TAKES IT FROM authenticated. Two kinds of entry:
--
--   * things a visitor genuinely calls (fold a search term, normalise a phone);
--   * things an RLS POLICY calls on their behalf. `is_manager()` and
--     `product_visible()` appear inside the policies on anon-readable tables,
--     and a policy is evaluated as the querying role — so without these grants
--     the catalogue returns nothing at all, to everybody.
grant execute on function public.is_manager()               to anon, authenticated;
grant execute on function public.product_visible(uuid)      to anon, authenticated;
grant execute on function public.normalize_phone(text)      to anon, authenticated;
grant execute on function public.fold_arabic(text)          to anon, authenticated;
grant execute on function public.is_eg_mobile(text)         to anon, authenticated;
grant execute on function public.specs_for_category(uuid)   to anon, authenticated;
grant execute on function public.tier_unit_price(uuid, int) to anon, authenticated;

-- Manager-side only: called from the triggers that fire when a manager edits a
-- product or its price ladder. A trigger function itself needs no EXECUTE, but
-- the calls it makes DO run as the person who caused the trigger.
grant execute on function public.my_role()                     to authenticated;
grant execute on function public.pricing_complete(uuid)        to authenticated;
grant execute on function public.refresh_product_prices(uuid)  to authenticated;

-- quote_product() and price_quote() arrive in 20260810100008 and
-- create_order_request() in 20260810100009, each granted there.
