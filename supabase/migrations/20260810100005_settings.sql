-- ============================================================================
--  إعدادات الموقع — صف واحد
--
--  Anon-readable, so EVERY column here must be something a passer-by is meant
--  to dial, copy, open or be quoted. A supplier note or a cost price goes in
--  public.product_private — see the rule in 20260810100000_schema.sql, and the
--  automated check in tools/schema-check/verify.mjs that enforces it.
-- ============================================================================

create table if not exists public.site_settings (
  id boolean primary key default true check (id),

  brand_name_ar text not null default 'نكست كامباين',
  brand_name_en text default 'Next Campaign',
  tagline_ar    text default 'مطبوعات وهدايا دعائية تحمل اسمك',

  whatsapp_phone text,
  hotline        text,
  email          text,
  address_ar     text,
  maps_url       text,
  working_hours_ar text,

  currency text not null default 'ج.م',

  -- Never hardcode 14 anywhere. The rate is snapshotted onto every order, so a
  -- change next year does not rewrite last year's totals.
  vat_rate          numeric(5,4) not null default 0.14 check (vat_rate >= 0 and vat_rate < 1),
  -- Whether the prices in the catalogue already contain the VAT. Getting this
  -- wrong is a per-order argument, so it is a stored decision shown in the UI,
  -- not an assumption.
  prices_include_vat boolean not null default false,

  -- "معندكش ملف vector؟ إحنا نعمله بـX" — turns the most common complaint in
  -- this trade into a revenue line.
  artwork_service_fee numeric(10,2),
  min_order_value     numeric(10,2),

  quote_promise_ar text default 'هنبعتلك عرض السعر خلال ٢٤ ساعة',
  rush_note_ar     text,

  facebook_url  text,
  instagram_url text,
  tiktok_url    text,
  linkedin_url  text,

  og_default_image text,
  updated_at timestamptz not null default now()
);

drop trigger if exists site_settings_touch on public.site_settings;
create trigger site_settings_touch before update on public.site_settings
  for each row execute function public.touch_updated_at();

insert into public.site_settings (id) values (true) on conflict (id) do nothing;
