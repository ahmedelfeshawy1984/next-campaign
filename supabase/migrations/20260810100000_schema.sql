-- ============================================================================
--  نكست كامباين — الجداول والأنواع الأساسية
--
--  Every statement here is re-runnable: this file is pasted into a live SQL
--  editor by a non-programmer, sometimes twice, and a second run must be a
--  no-op rather than an error wall.
-- ============================================================================

-- >>> shared-with-clinic
create extension if not exists "pgcrypto";
-- <<< shared-with-clinic

-- ---------------------------------------------------------------- enums ----

-- The `duplicate_object` guard makes this re-runnable, but it ALSO silently
-- accepts a type of the same name that means something else — which is how a
-- sibling project ended up with another app's ('promoter','manager','director')
-- and no error anywhere. The add-value lines are the repair: no-ops on a clean
-- install, and a fix on a colliding one.
-- >>> shared-with-clinic
do $$ begin create type public.user_role as enum ('customer','manager');
exception when duplicate_object then null; end $$;

alter type public.user_role add value if not exists 'customer';
alter type public.user_role add value if not exists 'manager';
-- <<< shared-with-clinic

-- How a spec is rendered and filtered. Drives the generated admin form.
do $$ begin create type public.spec_kind as enum ('number','bool','enum','text');
exception when duplicate_object then null; end $$;

-- ------------------------------------------------------------- helpers ----

-- >>> shared-with-clinic
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;
-- <<< shared-with-clinic

-- ------------------------------------------------------------ profiles ----

-- Mirrors auth.users. Only managers sign in through a password in v1; the
-- customer value exists from day one because anonymous upload sessions land
-- here too, and because customer accounts later should be a screen, not a
-- migration.
-- >>> shared-with-clinic
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  role       public.user_role not null default 'customer',
  full_name  text not null,
  phone      text unique,
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);
-- <<< shared-with-clinic

-- ---------------------------------------------------------- categories ----

-- One level of nesting, deliberately. "أكواب" under "دريك وير" is useful;
-- four levels is a taxonomy nobody maintains and a breadcrumb nobody reads.
create table if not exists public.categories (
  id         uuid primary key default gen_random_uuid(),
  slug       text not null unique,
  name_ar    text not null,
  name_en    text,
  blurb_ar   text,
  icon       text,
  cover_url  text,
  parent_id  uuid references public.categories(id) on delete set null,
  sort_order int not null default 0,
  is_active  boolean not null default true,
  seo_title_ar text,
  seo_desc_ar  text
);

create index if not exists categories_parent_idx on public.categories(parent_id);

-- ----------------------------------------------------------- occasions ----

-- An OPEN set, and that is the whole reason it is a table rather than an enum
-- or a pair of booleans: marketing will add the fortieth one next Ramadan, and
-- that has to be a row, not a deploy.
create table if not exists public.occasions (
  id         uuid primary key default gen_random_uuid(),
  slug       text not null unique,
  name_ar    text not null,
  name_en    text,
  blurb_ar   text,
  cover_url  text,
  -- Seasonal surfacing. Both null = shown all year.
  starts_on  date,
  ends_on    date,
  sort_order int not null default 0,
  is_active  boolean not null default true,
  seo_title_ar text,
  seo_desc_ar  text
);

-- ------------------------------------------------------------ products ----

-- Specs are TYPED COLUMNS, not EAV and not a jsonb blob. Same three reasons as
-- the sibling project, in order of weight:
--   1. Every facet in the filter is a numeric range. In EAV that is a self-join
--      per facet plus a pivot, which the Supabase query builder cannot express
--      — so every filter becomes a bespoke RPC.
--   2. In EAV every value is text, and '9' > '80' is true in text. A range
--      filter on a text column is silently wrong rather than loudly broken.
--   3. quote_product() reads the row flat.
-- "The owner adds a product without a developer" is met by `spec_defs`, which
-- drives the form, the spec sheet and the filters off table rows instead of
-- code — see 20260810100004_specs.sql.
--
-- PRINTING configuration is deliberately NOT here and NOT in spec_defs. Print
-- methods, positions, colour counts and cliché fees are arithmetic the price
-- engine does, not attributes a page renders. See 20260810100002_printing.sql.
create table if not exists public.products (
  id          uuid primary key default gen_random_uuid(),
  -- The URL. Shared on WhatsApp, so it outlives every rename — treat as
  -- immutable and add a row to product_slug_aliases when it must change.
  slug        text not null unique,
  category_id uuid not null references public.categories(id),
  sku         text,

  name_ar        text not null,
  name_en        text,
  short_pitch_ar text,
  short_pitch_en text,
  description_ar text,
  description_en text,

  -- The audience axis. A closed set of exactly two, so two booleans rather
  -- than a table: it drives routing (/corporate vs /gifts) and must be
  -- indexable. A third audience would be an `alter table` — correct, because a
  -- third audience is a business change.
  for_corporate  boolean not null default true,
  for_individual boolean not null default false,

  moq            int not null default 1 check (moq >= 1),
  max_positions  int not null default 1 check (max_positions >= 1),
  max_text_lines int not null default 1 check (max_text_lines >= 0),
  allows_logo    boolean not null default true,
  allows_text    boolean not null default true,

  lead_days_min int check (lead_days_min is null or lead_days_min >= 0),
  lead_days_max int check (lead_days_max is null or lead_days_max >= 0),

  -- Maintained by a trigger in 20260810100003_pricing.sql, NOT generated,
  -- because they read another table. A trigger can drift where a generated
  -- column cannot, which is exactly why the harness asserts them after insert,
  -- update AND delete of a tier.
  --   price_at_moq — what this actually costs at the cheapest legal quantity.
  --                  Every sort and filter uses THIS one.
  --   price_from   — the lowest rung of the ladder, shown as "بينزل لـ".
  -- A card that advertises the 1000-piece price to someone buying 50 is the
  -- MOQ trap, and using price_from to sort is how you build it by accident.
  price_at_moq numeric(10,2),
  price_from   numeric(10,2),

  is_published boolean not null default false,  -- draft while the owner types
  is_available boolean not null default true,   -- متاح / خلص
  is_featured  boolean not null default false,

  cover_url text,

  -- ---- specs. All nullable: unknown is not zero. ----
  material_ar     text,
  dimensions_ar   text,
  weight_g        int     check (weight_g       is null or weight_g       between 1 and 100000),
  capacity_ml     int     check (capacity_ml    is null or capacity_ml    between 1 and 20000),
  paper_gsm       int     check (paper_gsm      is null or paper_gsm      between 30 and 600),
  page_count      int     check (page_count     is null or page_count     between 1 and 2000),
  usb_capacity_gb int     check (usb_capacity_gb is null or usb_capacity_gb between 1 and 2048),
  battery_mah     int     check (battery_mah    is null or battery_mah    between 100 and 100000),
  pack_size       int     check (pack_size      is null or pack_size      >= 1),
  warranty_months int     check (warranty_months is null or warranty_months between 0 and 240),
  origin_ar       text,
  is_eco          boolean,

  -- Free-text marketing bullets. Rendered on the detail page; NEVER filtered
  -- and NEVER priced. This is the pressure valve that stops the real specs —
  -- and the printing tables — from being dissolved into a blob later.
  extra_specs jsonb not null default '{}'::jsonb,

  -- Arabic search without hamza/ta-marbuta grief: أ إ آ → ا, ة → ه, ى → ي, and
  -- tashkeel dropped. `foldArabic` in web/lib/arabic.ts must fold the same way,
  -- or the search box silently returns nothing for the words people type.
  -- `to` is deliberately SHORTER than `from`: translate() deletes any source
  -- character with no counterpart, so the five letters are mapped and the eight
  -- tashkeel marks are dropped entirely. Replacing them with spaces instead
  -- would split "مُحرِّك" into three unmatchable words.
  search_key text generated always as (
    translate(
      lower(coalesce(name_ar,'') || ' ' || coalesce(name_en,'') || ' ' || coalesce(sku,'')),
      'أإآةىًٌٍَُِّْ',
      'اااهي'
    )
  ) stored,

  seo_title_ar text,
  seo_desc_ar  text,

  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  check (lead_days_max is null or lead_days_min is null or lead_days_max >= lead_days_min)
);

drop trigger if exists products_touch on public.products;
create trigger products_touch before update on public.products
  for each row execute function public.touch_updated_at();

-- Partial indexes: nothing filters unpublished rows except the owner, and his
-- catalogue is small enough to seq-scan.
create index if not exists products_price_idx      on public.products(price_at_moq) where is_published;
create index if not exists products_category_idx   on public.products(category_id)  where is_published;
create index if not exists products_corporate_idx  on public.products(for_corporate)  where is_published;
create index if not exists products_individual_idx on public.products(for_individual) where is_published;
create index if not exists products_search_idx     on public.products(search_key)   where is_published;

-- A slug shared on WhatsApp lives in that chat forever. One table plus a 301
-- in middleware is the whole insurance policy.
create table if not exists public.product_slug_aliases (
  old_slug   text primary key,
  product_id uuid not null references public.products(id) on delete cascade
);

-- ------------------------------------------------------------- options ----

-- Deliberately NOT a variant matrix. A t-shirt in 6 colours x 5 sizes is 30
-- rows in a proper matrix; the owner will enter one and stop. Two flat tables,
-- customer picks one item per group: 11 rows instead of 30.
--
-- What that costs is per-combination stock, which the owner does not track
-- anyway — same trade as the sibling project's "متاح/خلص، من غير عدّ قطع".
create table if not exists public.product_option_groups (
  id          uuid primary key default gen_random_uuid(),
  product_id  uuid not null references public.products(id) on delete cascade,
  code        text not null,          -- color · size · capacity
  label_ar    text not null,
  label_en    text,
  is_required boolean not null default true,
  sort_order  int not null default 0,
  unique (product_id, code)
);

create table if not exists public.product_option_items (
  id        uuid primary key default gen_random_uuid(),
  group_id  uuid not null references public.product_option_groups(id) on delete cascade,
  value     text not null,
  label_ar  text not null,
  label_en  text,
  hex       text check (hex is null or hex ~ '^#[0-9A-Fa-f]{6}$'),
  -- What makes 32 GB cost more than 8 GB without a variant explosion.
  price_delta numeric(10,2) not null default 0,
  -- An option that has run out stays VISIBLE and greyed. One that silently
  -- disappears reads as "they never had it".
  is_available boolean not null default true,
  image_url  text,
  sort_order int not null default 0,
  unique (group_id, value)
);

create index if not exists option_groups_parent_idx on public.product_option_groups(product_id);
create index if not exists option_items_parent_idx  on public.product_option_items(group_id);

-- -------------------------------------------------------------- images ----

create table if not exists public.product_images (
  id             uuid primary key default gen_random_uuid(),
  product_id     uuid not null references public.products(id) on delete cascade,
  -- Tap a colour, the gallery follows. Null = shown for every option.
  option_item_id uuid references public.product_option_items(id) on delete set null,
  url            text not null,
  alt_ar         text,
  sort_order     int not null default 0
);

create index if not exists product_images_parent_idx on public.product_images(product_id);

-- ----------------------------------------------------------- occasions ----

create table if not exists public.product_occasions (
  product_id  uuid not null references public.products(id)  on delete cascade,
  occasion_id uuid not null references public.occasions(id) on delete cascade,
  -- The one badge printed on the catalogue card. A card with four badges says
  -- nothing, so the database enforces at most one.
  is_primary  boolean not null default false,
  primary key (product_id, occasion_id)
);

create unique index if not exists product_occasions_one_primary
  on public.product_occasions(product_id) where is_primary;

-- ------------------------------------------------------------- private ----

-- THE RULE, and it will be tested harder here than in any sibling project,
-- because a promotional-gifts business is entirely about margin:
--
--   public.products, public.categories, public.occasions, public.print_methods,
--   public.product_price_tiers and public.site_settings are ANON-READABLE.
--   No cost price, no supplier, no margin, no internal note may EVER be added
--   to them. They go here, and this table gets no anon grant, ever.
--
-- tools/schema-check/verify.mjs enforces this by scanning information_schema
-- for column names matching cost|supplier|margin|profit|purchase|wholesale on
-- the anon-readable list, so the rule fails the build instead of relying on
-- somebody remembering it.
create table if not exists public.product_private (
  product_id    uuid primary key references public.products(id) on delete cascade,
  cost_price    numeric(10,2),
  supplier_name text,
  supplier_ref  text,
  internal_note text,
  updated_at    timestamptz not null default now()
);

drop trigger if exists product_private_touch on public.product_private;
create trigger product_private_touch before update on public.product_private
  for each row execute function public.touch_updated_at();
