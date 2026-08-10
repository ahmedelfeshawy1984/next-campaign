-- ============================================================================
--  شرايح الكميات — محرك التسعير
--
--  The ladder is the product. A promotional-gifts customer does not ask "how
--  much is a mug", they ask "how much is a mug if I take 250". Everything here
--  exists to make that answer instant, consistent and impossible to typo into
--  a silent overcharge.
-- ============================================================================

-- HALF-OPEN INTERVALS. There is no max_qty column and there never will be:
-- two columns that must agree will one day disagree, and the day they do it is
-- money. The upper bound of a tier is the NEXT row's min_qty.
--
-- This is the sibling project's "المدينة متخزنة، والمحافظة لأ" applied to
-- pricing — store the one fact, derive the other.
create table if not exists public.product_price_tiers (
  id         uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  min_qty    int not null check (min_qty >= 1),
  unit_price numeric(10,2) not null check (unit_price >= 0),
  unique (product_id, min_qty)
);

create index if not exists price_tiers_parent_idx
  on public.product_price_tiers(product_id, min_qty desc);

-- ---------------------------------------------------------------------------
--  The lookup, written once and used by price_quote(), the denormalisation
--  trigger and the harness. Three copies of `order by min_qty desc limit 1`
--  is three chances to write `asc`.
-- ---------------------------------------------------------------------------
create or replace function public.tier_unit_price(p_product uuid, p_qty int)
returns numeric
language sql stable as $$
  select t.unit_price
    from public.product_price_tiers t
   where t.product_id = p_product
     and t.min_qty <= p_qty
   order by t.min_qty desc
   limit 1
$$;

-- ---------------------------------------------------------------------------
--  Denormalisation onto products.
--
--  These two columns cannot be `generated always as` because they read another
--  table, so a trigger maintains them. That is a real departure from a
--  generated column and it carries a real risk — a trigger can drift where a
--  generated column cannot — which is why the harness re-asserts them after
--  INSERT, UPDATE *and DELETE* of a tier, and after a change to products.moq.
-- ---------------------------------------------------------------------------
create or replace function public.refresh_product_prices(p_product uuid)
returns void
language plpgsql as $$
declare v_moq int;
begin
  select moq into v_moq from public.products where id = p_product;
  if v_moq is null then return; end if;   -- product already gone

  update public.products p
     set price_at_moq = public.tier_unit_price(p_product, v_moq),
         price_from   = (select min(unit_price) from public.product_price_tiers
                          where product_id = p_product)
   where p.id = p_product;
end $$;

create or replace function public.tiers_refresh_prices()
returns trigger language plpgsql as $$
begin
  perform public.refresh_product_prices(coalesce(new.product_id, old.product_id));
  return null;
end $$;

drop trigger if exists price_tiers_refresh on public.product_price_tiers;
create trigger price_tiers_refresh
  after insert or update or delete on public.product_price_tiers
  for each row execute function public.tiers_refresh_prices();

-- moq moving changes which rung price_at_moq reads.
create or replace function public.products_refresh_prices()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' or old.moq is distinct from new.moq then
    perform public.refresh_product_prices(new.id);
  end if;
  return null;
end $$;

drop trigger if exists products_refresh_prices on public.products;
create trigger products_refresh_prices
  after insert or update of moq on public.products
  for each row execute function public.products_refresh_prices();

-- ---------------------------------------------------------------------------
--  Completeness.
--
--  A published product with no tiers, no print method or no position is a
--  product page whose "اطلب" button does nothing. Defined before the two
--  triggers that call it.
-- ---------------------------------------------------------------------------
create or replace function public.pricing_complete(p_product uuid)
returns boolean
language sql stable as $$
  select
    -- a rung at or below MOQ, so the cheapest legal quantity has a price
    public.tier_unit_price(p_product, (select moq from public.products where id = p_product))
      is not null
    and exists (select 1 from public.product_print_methods where product_id = p_product)
    and exists (select 1 from public.print_positions      where product_id = p_product)
$$;

-- ---------------------------------------------------------------------------
--  Ladder validation.
--
--  A tier whose unit_price goes UP as min_qty rises is a typo that silently
--  overcharges, and nobody notices until a customer does the arithmetic. It is
--  not a business decision anyone has ever meant to make.
--
--  Deferred to commit deliberately: replacing a whole ladder is
--  "delete all, insert new" in one transaction, and an immediate trigger would
--  reject the intermediate state that every such edit passes through.
-- ---------------------------------------------------------------------------
create or replace function public.validate_price_ladder()
returns trigger language plpgsql as $$
declare
  v_product uuid := coalesce(new.product_id, old.product_id);
  v_bad     int;
  v_published boolean;
begin
  if not exists (select 1 from public.products where id = v_product) then
    return null;   -- the product itself was deleted; the cascade took the tiers
  end if;

  select count(*) into v_bad
    from (
      select unit_price,
             lag(unit_price) over (order by min_qty) as prev
        from public.product_price_tiers
       where product_id = v_product
    ) s
   where s.prev is not null and s.unit_price > s.prev;

  if v_bad > 0 then
    raise exception 'PRICE_LADDER_NOT_DESCENDING'
      using hint = 'سعر القطعة لازم ينزل أو يفضل ثابت كل ما الكمية تزيد';
  end if;

  -- A published product that just lost the tier covering its MOQ is a live
  -- page whose price is NULL. Catch it here rather than on the customer's
  -- screen.
  select is_published into v_published from public.products where id = v_product;
  if v_published and not public.pricing_complete(v_product) then
    raise exception 'PRICING_INCOMPLETE'
      using hint = 'المنتج منشور — لازم شريحة سعر عند الحد الأدنى أو تحته';
  end if;

  return null;
end $$;

-- ---------------------------------------------------------------------------
--  The publish gate. The database refuses an unfinished product rather than
--  the UI apologising for it.
-- ---------------------------------------------------------------------------
create or replace function public.products_publish_gate()
returns trigger language plpgsql as $$
begin
  -- Only on the transition, and only on a change to MOQ. Without this the
  -- denormalisation trigger's own `update products` would re-run the gate on
  -- every tier edit and reject the intermediate states of a legitimate one.
  if new.is_published and (
       tg_op = 'INSERT'
       or old.is_published is distinct from new.is_published
       or old.moq is distinct from new.moq
     ) then
    if not public.pricing_complete(new.id) then
      raise exception 'PRICING_INCOMPLETE'
        using hint = 'قبل النشر: شريحة سعر عند الحد الأدنى، وطريقة طباعة، ومكان طباعة';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists products_publish_gate on public.products;
create trigger products_publish_gate
  before insert or update on public.products
  for each row execute function public.products_publish_gate();

-- Declared last: it references pricing_complete(), which is defined above.
drop trigger if exists price_tiers_validate on public.product_price_tiers;
create constraint trigger price_tiers_validate
  after insert or update or delete on public.product_price_tiers
  deferrable initially deferred
  for each row execute function public.validate_price_ladder();
