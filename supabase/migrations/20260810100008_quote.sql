-- ============================================================================
--  محرك التسعير — كتالوج الأسعار والحساب المُلزِم
--
--  ⚠  This file sorts AFTER 20260810100006_rls.sql, which revoked execute on
--     every function from anon. It therefore carries its own grants, at the
--     bottom. Do not move it earlier.
--
--  THE ARITHMETIC LIVES HERE, ONCE.
--
--  price_quote() below is the authority. web/lib/pricing.ts computes the same
--  numbers in the browser so the total moves as the customer drags the
--  quantity — but it is a dumb evaluator over data this file produced, not a
--  second set of rules. tools/schema-check/verify.mjs fuzzes 200 random
--  selections through both and asserts they agree TO THE PIASTRE. Two
--  implementations are only acceptable when a test proves they are one.
-- ============================================================================

-- Is the colour count something the customer chooses, and therefore something
-- they pay for?
--
-- Only two of the four models. Laser engraves the material — there is no
-- colour, and charging for one would be charging for a choice we did not
-- offer. Sublimation is one price whatever the artwork. Screen printing pays
-- per spot; embroidery pays per thread. Getting this wrong makes
-- addon_per_color dead data on embroidery rows, which is the silent kind of
-- pricing bug.
create or replace function public.method_uses_color_count(p_model public.print_color_model)
returns boolean
language sql immutable as $$
  select p_model in ('spot', 'thread')
$$;

-- ---------------------------------------------------------------------------
--  The effective ceiling on colours: the position may override the product,
--  which may override the method's default. NULL anywhere means "no limit at
--  this level, ask the next one".
-- ---------------------------------------------------------------------------
create or replace function public.effective_max_colors(
  p_product uuid, p_method text, p_position uuid default null
) returns int
language sql stable as $$
  select coalesce(
    (select ppm.max_colors from public.position_print_methods ppm
      where ppm.position_id = p_position and ppm.method_code = p_method),
    (select pm.max_colors from public.product_print_methods pm
      where pm.product_id = p_product and pm.method_code = p_method),
    (select m.default_max_colors from public.print_methods m where m.code = p_method)
  )
$$;

-- ---------------------------------------------------------------------------
--  Does this position accept this method?
--
--  THE CONVENTION, implemented in exactly one place so the site, the RPC and
--  the harness cannot disagree: a position with ZERO rows in
--  position_print_methods accepts every method the PRODUCT supports. A
--  position WITH rows accepts only those.
--
--  This is what stops an N x M seed for the 95% of products where every method
--  works everywhere, while keeping the escape hatch for the mug handle that
--  takes pad printing but not sublimation.
-- ---------------------------------------------------------------------------
create or replace function public.position_allows_method(p_position uuid, p_method text)
returns boolean
language sql stable as $$
  select case
    when not exists (select 1 from public.position_print_methods
                      where position_id = p_position)
    then exists (
      select 1 from public.print_positions pos
        join public.product_print_methods pm
          on pm.product_id = pos.product_id and pm.method_code = p_method
       where pos.id = p_position)
    else exists (select 1 from public.position_print_methods
                  where position_id = p_position and method_code = p_method)
  end
$$;

-- ---------------------------------------------------------------------------
--  quote_product() — the PRICE BOOK for one product, in one round trip.
--
--  Everything the configurator needs to compute a total without another
--  request: every rung, every option, every fee, every ceiling, every waiver.
--  The browser then does arithmetic over data, never over rules of its own.
-- ---------------------------------------------------------------------------
create or replace function public.quote_product(p_product uuid)
returns jsonb
language sql stable as $$
  select case when p.id is null then null else jsonb_build_object(
    'product_id', p.id,
    'slug', p.slug,
    'name_ar', p.name_ar,
    'moq', p.moq,
    'max_positions', p.max_positions,
    'max_text_lines', p.max_text_lines,
    'allows_logo', p.allows_logo,
    'allows_text', p.allows_text,
    'lead_days_min', p.lead_days_min,
    'lead_days_max', p.lead_days_max,
    'currency', s.currency,
    'vat_rate', s.vat_rate,
    'prices_include_vat', s.prices_include_vat,

    'tiers', coalesce((
      select jsonb_agg(jsonb_build_object('min_qty', t.min_qty, 'unit_price', t.unit_price)
                       order by t.min_qty)
        from public.product_price_tiers t where t.product_id = p.id), '[]'::jsonb),

    'option_groups', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', g.id, 'code', g.code, 'label_ar', g.label_ar,
        'is_required', g.is_required,
        'items', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', i.id, 'value', i.value, 'label_ar', i.label_ar, 'hex', i.hex,
            'price_delta', i.price_delta, 'is_available', i.is_available,
            'image_url', i.image_url) order by i.sort_order)
            from public.product_option_items i where i.group_id = g.id), '[]'::jsonb)
      ) order by g.sort_order)
        from public.product_option_groups g where g.product_id = p.id), '[]'::jsonb),

    'methods', coalesce((
      select jsonb_agg(jsonb_build_object(
        'code', m.code, 'name_ar', m.name_ar, 'blurb_ar', m.blurb_ar,
        'color_model', m.color_model,
        'uses_color_count', public.method_uses_color_count(m.color_model),
        'needs_vector', m.needs_vector,
        'setup_fee', pm.setup_fee,
        'setup_fee_per_color', pm.setup_fee_per_color,
        'setup_fee_waived_over_qty', pm.setup_fee_waived_over_qty,
        'unit_addon', pm.unit_addon,
        'addon_per_color', pm.addon_per_color,
        'max_colors', public.effective_max_colors(p.id, m.code, null),
        'method_min_qty', pm.method_min_qty,
        'is_default', pm.is_default
      ) order by m.sort_order)
        from public.product_print_methods pm
        join public.print_methods m on m.code = pm.method_code
       where pm.product_id = p.id and m.is_active), '[]'::jsonb),

    'positions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pos.id, 'code', pos.code, 'name_ar', pos.name_ar,
        'area_w_mm', pos.area_w_mm, 'area_h_mm', pos.area_h_mm,
        'preview_x', pos.preview_x, 'preview_y', pos.preview_y,
        'preview_w', pos.preview_w, 'preview_h', pos.preview_h,
        'preview_rotate', pos.preview_rotate,
        'is_default', pos.is_default,
        -- Resolved here, not in the browser: the "empty means all" rule has
        -- exactly one implementation and this is where it is applied.
        'methods', coalesce((
          select jsonb_agg(jsonb_build_object(
            'code', pm2.method_code,
            'max_colors', public.effective_max_colors(p.id, pm2.method_code, pos.id),
            'area_w_mm', coalesce(ppm.area_w_mm, pos.area_w_mm),
            'area_h_mm', coalesce(ppm.area_h_mm, pos.area_h_mm)))
            from public.product_print_methods pm2
            left join public.position_print_methods ppm
              on ppm.position_id = pos.id and ppm.method_code = pm2.method_code
           where pm2.product_id = p.id
             and public.position_allows_method(pos.id, pm2.method_code)), '[]'::jsonb)
      ) order by pos.sort_order)
        from public.print_positions pos where pos.product_id = p.id), '[]'::jsonb),

    'fonts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', f.key, 'name_ar', f.name_ar, 'css_family', f.css_family,
        'script', f.script, 'is_display', f.is_display) order by f.sort_order)
        from public.fonts f where f.is_active), '[]'::jsonb)
  ) end
    from public.products p
    left join public.site_settings s on s.id
   where p.id = p_product and (p.is_published or public.is_manager())
$$;

-- ---------------------------------------------------------------------------
--  price_quote() — THE AUTHORITY.
--
--  Returns amounts AND a list of stable error codes rather than raising. The
--  configurator needs to say "screen printing needs at least 50" while the
--  customer is still choosing; an exception can only say "no".
--
--  The codes are the same kind of contract as the sibling project's PRED_LOCKED
--  / RATE_LIMITED markers: server-side truth, translated once on the client.
-- ---------------------------------------------------------------------------
create or replace function public.price_quote(
  p_product         uuid,
  p_qty             int,
  p_method          text default null,
  p_colors          int default 1,
  p_position_ids    uuid[] default '{}',
  p_option_item_ids uuid[] default '{}'
) returns jsonb
language plpgsql stable as $$
declare
  v_moq int;
  v_max_positions int;
  v_published boolean;
  v_uses_colors boolean := false;
  v_option_unavailable boolean := false;
  v_option_match int := 0;
  v_option_sent int := 0;
  v_position_sent int := 0;
  v_colors int := greatest(coalesce(p_colors, 1), 1);
  v_max_colors int;
  v_tier numeric(10,2);
  v_options numeric(10,2) := 0;
  v_addon numeric(10,2) := 0;
  v_per_piece numeric(12,2);
  v_subtotal numeric(12,2);
  v_setup numeric(12,2) := 0;
  v_pre_vat numeric(12,2);
  v_vat numeric(12,2);
  v_vat_rate numeric(5,4);
  v_inclusive boolean;
  v_currency text;
  v_errors text[] := '{}';
  m record;
  pos record;
begin
  select p.moq, p.max_positions, p.is_published
    into v_moq, v_max_positions, v_published
    from public.products p where p.id = p_product;

  if v_moq is null then
    return jsonb_build_object('ok', false, 'errors', array['PRODUCT_NOT_FOUND']);
  end if;

  select s.vat_rate, s.prices_include_vat, s.currency
    into v_vat_rate, v_inclusive, v_currency
    from public.site_settings s where s.id;
  v_vat_rate := coalesce(v_vat_rate, 0);

  if p_qty is null or p_qty < 1 then
    return jsonb_build_object('ok', false, 'errors', array['QTY_INVALID']);
  end if;
  if p_qty < v_moq then
    v_errors := array_append(v_errors, 'QTY_BELOW_MOQ');
  end if;

  -- ---- the rung -----------------------------------------------------------
  v_tier := public.tier_unit_price(p_product, p_qty);
  if v_tier is null then
    v_errors := array_append(v_errors, 'NO_PRICE_TIER');
    v_tier := 0;
  end if;

  -- ---- options ------------------------------------------------------------
  v_option_sent := coalesce(array_length(p_option_item_ids, 1), 0);

  select coalesce(sum(i.price_delta), 0),
         coalesce(bool_or(not i.is_available), false),
         count(*)::int
    into v_options, v_option_unavailable, v_option_match
    from public.product_option_items i
    join public.product_option_groups g on g.id = i.group_id
   where i.id = any(p_option_item_ids) and g.product_id = p_product;

  if v_option_unavailable then
    v_errors := array_append(v_errors, 'OPTION_UNAVAILABLE');
  end if;

  -- An option id belonging to a DIFFERENT product must not silently price as
  -- zero: that is a stale configuration, and pricing it as free is how a
  -- customer ends up quoted for something we never agreed to make.
  if v_option_match <> v_option_sent then
    v_errors := array_append(v_errors, 'OPTION_NOT_ON_PRODUCT');
  end if;

  -- ---- the method ---------------------------------------------------------
  if p_method is not null then
    select pm.*, pmeth.color_model into m
      from public.product_print_methods pm
      join public.print_methods pmeth on pmeth.code = pm.method_code
     where pm.product_id = p_product and pm.method_code = p_method;

    if not found then
      v_errors := array_append(v_errors, 'METHOD_NOT_SUPPORTED');
    else
      v_uses_colors := public.method_uses_color_count(m.color_model);
      if not v_uses_colors then
        v_colors := 1;   -- laser has no colour to charge for
      end if;

      v_max_colors := public.effective_max_colors(p_product, p_method, null);
      if v_uses_colors and v_max_colors is not null and v_colors > v_max_colors then
        v_errors := array_append(v_errors, 'TOO_MANY_COLORS');
        v_colors := v_max_colors;
      end if;

      if m.method_min_qty is not null and p_qty < m.method_min_qty then
        v_errors := array_append(v_errors, 'QTY_BELOW_METHOD_MIN');
      end if;

      v_addon := m.unit_addon
               + case when v_uses_colors then (v_colors - 1) * m.addon_per_color else 0 end;
    end if;
  end if;

  -- ---- positions and their setup fees -------------------------------------
  v_position_sent := coalesce(array_length(p_position_ids, 1), 0);
  if v_position_sent > v_max_positions then
    v_errors := array_append(v_errors, 'TOO_MANY_POSITIONS');
  end if;

  if p_method is not null and m.method_code is not null then
    for pos in
      select pp.id from public.print_positions pp
       where pp.id = any(p_position_ids) and pp.product_id = p_product
    loop
      if not public.position_allows_method(pos.id, p_method) then
        v_errors := array_append(v_errors, 'POSITION_METHOD_NOT_ALLOWED');
      end if;

      -- The waiver is >=, not >. A customer ordering exactly the threshold
      -- expects the free cliché, and arguing about it costs more than it saves.
      if m.setup_fee_waived_over_qty is not null and p_qty >= m.setup_fee_waived_over_qty then
        null;
      else
        v_setup := v_setup
                 + m.setup_fee * case when m.setup_fee_per_color then v_colors else 1 end;
      end if;
    end loop;

    -- A position id that is not on this product is a stale configuration, not
    -- a free print.
    if v_position_sent <> (
         select count(*)::int from public.print_positions pp
          where pp.id = any(p_position_ids) and pp.product_id = p_product)
    then
      v_errors := array_append(v_errors, 'POSITION_NOT_ON_PRODUCT');
    end if;
  end if;

  -- ---- the total ----------------------------------------------------------
  v_per_piece := v_tier + v_options + v_addon;
  v_subtotal  := v_per_piece * p_qty;
  v_pre_vat   := v_subtotal + v_setup;
  v_vat       := case when v_inclusive then 0 else round(v_pre_vat * v_vat_rate, 2) end;

  return jsonb_build_object(
    'ok', cardinality(v_errors) = 0,
    'errors', v_errors,
    'qty', p_qty,
    'colors', v_colors,
    'tier_unit_price', v_tier,
    'options_delta', v_options,
    'method_addon', v_addon,
    'unit_price', v_per_piece,
    'subtotal', v_subtotal,
    'setup_total', v_setup,
    'pre_vat', v_pre_vat,
    'vat_rate', v_vat_rate,
    'prices_include_vat', v_inclusive,
    'vat_amount', v_vat,
    'total', v_pre_vat + v_vat,
    'currency', v_currency
  );
end $$;

-- ------------------------------------------------------------ الصلاحيات ----
--
-- Revoke from PUBLIC first, then grant BY NAME. The revoke matters: these
-- functions were created after 20260810100006_rls.sql ran, so they carry the
-- default PUBLIC grant and nothing has taken it away yet.
--
-- A visitor prices a product without an account — that is the whole point of
-- showing prices at all — so all five end up granted anyway here. The habit is
-- what protects the next function added to this file.
revoke execute on function public.method_uses_color_count(public.print_color_model) from public, anon;
revoke execute on function public.effective_max_colors(uuid, text, uuid)            from public, anon;
revoke execute on function public.position_allows_method(uuid, text)                from public, anon;
revoke execute on function public.quote_product(uuid)                               from public, anon;
revoke execute on function public.price_quote(uuid, int, text, int, uuid[], uuid[]) from public, anon;

grant execute on function public.method_uses_color_count(public.print_color_model) to anon, authenticated;
grant execute on function public.effective_max_colors(uuid, text, uuid)            to anon, authenticated;
grant execute on function public.position_allows_method(uuid, text)                to anon, authenticated;
grant execute on function public.quote_product(uuid)                               to anon, authenticated;
grant execute on function public.price_quote(uuid, int, text, int, uuid[], uuid[])  to anon, authenticated;
