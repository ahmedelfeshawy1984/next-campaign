-- ============================================================================
-- نكست كامباين — Next Campaign · complete database setup
--
-- GENERATED FILE — do not edit. Edit supabase/migrations/*.sql and re-run
--   node tools/build-setup.mjs
--
-- HOW TO USE
--   1. Supabase dashboard → SQL Editor → New query
--   2. Paste this whole file
--   3. Run
--
-- Safe to run more than once: every statement is idempotent.
-- ============================================================================

-- ## 20260810100000_schema.sql
-- ============================================================================
--  نكست كامباين — الجداول والأنواع الأساسية
--
--  Every statement here is re-runnable: this file is pasted into a live SQL
--  editor by a non-programmer, sometimes twice, and a second run must be a
--  no-op rather than an error wall.
-- ============================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------- enums ----

-- The `duplicate_object` guard makes this re-runnable, but it ALSO silently
-- accepts a type of the same name that means something else — which is how a
-- sibling project ended up with another app's ('promoter','manager','director')
-- and no error anywhere. The add-value lines are the repair: no-ops on a clean
-- install, and a fix on a colliding one.
do $$ begin create type public.user_role as enum ('customer','manager');
exception when duplicate_object then null; end $$;

alter type public.user_role add value if not exists 'customer';
alter type public.user_role add value if not exists 'manager';

-- How a spec is rendered and filtered. Drives the generated admin form.
do $$ begin create type public.spec_kind as enum ('number','bool','enum','text');
exception when duplicate_object then null; end $$;

-- ------------------------------------------------------------- helpers ----

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ------------------------------------------------------------ profiles ----

-- Mirrors auth.users. Only managers sign in through a password in v1; the
-- customer value exists from day one because anonymous upload sessions land
-- here too, and because customer accounts later should be a screen, not a
-- migration.
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  role       public.user_role not null default 'customer',
  full_name  text not null,
  phone      text unique,
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);

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

-- ## 20260810100001_auth_helpers.sql
-- ============================================================================
--  دوال مساعدة للصلاحيات والتطبيع
--
--  Every predicate used inside an RLS policy lives here, as SECURITY DEFINER
--  with a pinned search_path. Two reasons, both learned the hard way in the
--  sibling projects:
--
--    * A policy ON profiles that reads FROM profiles recurses forever. A
--      definer function is evaluated outside RLS and breaks the loop.
--    * An unpinned search_path lets anyone who can create a schema shadow
--      `profiles` with their own table and answer `is_manager()` themselves.
-- ============================================================================

create or replace function public.my_role()
returns public.user_role
language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.is_manager()
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'manager' and is_active
  )
$$;

-- ---------------------------------------------------------------------------
--  Phone normalisation. Mirrors `normalizePhone` in web/lib/phone.ts, character
--  for character, and the harness asserts the two agree on the same six
--  spellings. If they ever diverge, an order filed from a keyboard typing ٠١٠…
--  cannot be read back on /track by someone typing 010….
-- ---------------------------------------------------------------------------
create or replace function public.normalize_phone(p_raw text)
returns text
language plpgsql immutable as $$
declare v text;
begin
  if p_raw is null then return null; end if;

  -- Arabic-Indic ٠١٢… and Eastern-Arabic ۰۱۲… both reach us from real
  -- keyboards; fold them to ASCII, then keep digits only.
  v := translate(p_raw, '٠١٢٣٤٥٦٧٨٩', '0123456789');
  v := translate(v,     '۰۱۲۳۴۵۶۷۸۹', '0123456789');
  v := regexp_replace(v, '[^0-9]', '', 'g');

  if v like '0020%'                   then v := '0' || substr(v, 5); end if;
  if v like '20%'  and length(v) = 12 then v := '0' || substr(v, 3); end if;
  if length(v) = 10 and v like '1%'   then v := '0' || v;            end if;

  return v;
end $$;

-- Is this a real Egyptian mobile number? 010/011/012/015 are the only four
-- prefixes in service. Used by the order RPC, not by the browser alone —
-- client-side validation is a courtesy, not a gate.
create or replace function public.is_eg_mobile(p_raw text)
returns boolean
language sql immutable as $$
  select public.normalize_phone(p_raw) ~ '^01[0125][0-9]{8}$'
$$;

-- ---------------------------------------------------------------------------
--  Arabic folding, exposed as a function so the search box can fold the term
--  the same way the generated `products.search_key` column folded the data.
--  web/lib/arabic.ts is the third implementation and the harness asserts all
--  three agree.
-- ---------------------------------------------------------------------------
create or replace function public.fold_arabic(p_raw text)
returns text
language sql immutable as $$
  select translate(lower(coalesce(p_raw,'')), 'أإآةىًٌٍَُِّْ', 'اااهي')
$$;

-- ---------------------------------------------------------------------------
--  Mirrors the profiles row for every new auth user.
--
--  Anonymous sessions land here too — that is what signInAnonymously() creates,
--  and every artwork upload needs one. They get role 'customer' and a null
--  phone; 20260810100011_cleanup.sql sweeps the ones that never became an
--  order. Without the coalesce on full_name this trigger raises on every
--  anonymous sign-in and the uploader dies with a message nobody can read.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, role, full_name, phone)
  values (
    new.id,
    coalesce((new.raw_user_meta_data ->> 'role')::public.user_role, 'customer'),
    coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''), 'زائر'),
    nullif(public.normalize_phone(new.raw_user_meta_data ->> 'phone'), '')
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ## 20260810100002_printing.sql
-- ============================================================================
--  إعدادات الطباعة — الطرق والأماكن والخطوط
--
--  WHY THIS IS NOT spec_defs
--
--  spec_defs (20260810100004) answers "what do I display and filter?". Printing
--  answers "what does it cost and can we make it?" — it is a manufacturing and
--  pricing graph you do arithmetic over. Forcing fees into spec_defs would mean
--  a spec whose value is a price formula, which is the same EAV/jsonb pressure
--  the schema migration rejects, wearing a different hat.
--
--  So: real relational tables with real numeric columns, and price_quote() in
--  20260810100008 doing the arithmetic over them.
-- ============================================================================

-- How colour works for a method. This is doing real work that a
-- `supports_full_color boolean` cannot:
--   spot        — screen/pad printing. You pay per colour. Pick a count.
--   full_color  — sublimation/DTF/UV photo. One price regardless of the artwork.
--   single_tone — laser engraving. It burns the material; there IS no colour to
--                 choose, and offering one is a lie printed by the UI.
--   thread      — embroidery. A count of thread colours, priced differently
--                 from screen spots (digitising once, then per-thousand-stitch).
-- The configurator renders a different control per model, from this data.
do $$ begin create type public.print_color_model as enum
  ('spot','full_color','single_tone','thread');
exception when duplicate_object then null; end $$;

-- --------------------------------------------------------------- methods ----

create table if not exists public.print_methods (
  code        text primary key,   -- screen laser embroidery uv dtf sublimation
                                  -- transfer pad digital foil emboss
  name_ar     text not null,
  name_en     text,
  blurb_ar    text,
  color_model public.print_color_model not null,
  -- Drives the format requirement shown in the uploader. A customer who
  -- uploads a 200x200 Facebook JPEG for an 8 cm screen print has to be told
  -- BEFORE they submit, not after.
  needs_vector boolean not null default false,

  -- Defaults, so the admin form pre-fills 150 ج.م for a screen cliché and the
  -- owner only types when THIS product differs. Overrides live on
  -- product_print_methods.
  default_setup_fee  numeric(10,2) not null default 0 check (default_setup_fee >= 0),
  default_max_colors int check (default_max_colors is null or default_max_colors >= 1),

  sort_order int not null default 0,
  is_active  boolean not null default true
);

-- ------------------------------------------------------------- positions ----

create table if not exists public.print_positions (
  id         uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  code       text not null,        -- front back handle chest_right sleeve lid
  name_ar    text not null,        -- الوش · الضهر · الودن · صدر يمين · كم
  name_en    text,

  area_w_mm numeric(6,1) check (area_w_mm is null or area_w_mm > 0),
  area_h_mm numeric(6,1) check (area_h_mm is null or area_h_mm > 0),

  -- The live-preview box, as PERCENTAGES of the cover image. Five numbers is
  -- the entire cheap preview: a new product gets one by typing four values in
  -- the admin form, not by writing a component. This is the spec_defs spirit
  -- applied to rendering.
  --
  -- The expensive version — three.js with a UV-mapped model per product — needs
  -- a designer to produce assets for ~200 SKUs. The honest substitute is the
  -- artwork_review status, where a human sends a real proof.
  preview_x      numeric(5,2) check (preview_x is null or preview_x between 0 and 100),
  preview_y      numeric(5,2) check (preview_y is null or preview_y between 0 and 100),
  preview_w      numeric(5,2) check (preview_w is null or preview_w between 0 and 100),
  preview_h      numeric(5,2) check (preview_h is null or preview_h between 0 and 100),
  preview_rotate numeric(5,2) not null default 0,

  is_default boolean not null default false,
  sort_order int not null default 0,
  unique (product_id, code)
);

create index if not exists print_positions_parent_idx on public.print_positions(product_id);

-- --------------------------------------------- which methods this product ---

create table if not exists public.product_print_methods (
  product_id  uuid not null references public.products(id) on delete cascade,
  method_code text not null references public.print_methods(code) on delete cascade,

  -- الكليشيه. Charged once per position, not per piece.
  setup_fee           numeric(10,2) not null default 0 check (setup_fee >= 0),
  setup_fee_per_color boolean not null default false,
  -- "الكليشيه مجاني فوق ٥٠٠". Comparison is >=, not >, and the harness pins
  -- that: a customer ordering exactly the threshold expects the waiver.
  setup_fee_waived_over_qty int check (setup_fee_waived_over_qty is null
                                       or setup_fee_waived_over_qty >= 1),

  unit_addon      numeric(10,2) not null default 0 check (unit_addon >= 0),
  addon_per_color numeric(10,2) not null default 0 check (addon_per_color >= 0),

  max_colors    int check (max_colors is null or max_colors >= 1),
  -- Screen printing has its own floor regardless of the product's MOQ. Shown
  -- in the picker as a disabled card WITH THE REASON, never silently missing.
  method_min_qty int check (method_min_qty is null or method_min_qty >= 1),

  is_default boolean not null default false,
  primary key (product_id, method_code)
);

-- ------------------------------------- per-position overrides (optional) ----

-- THE RULE, documented here and asserted in the harness because it is a
-- convention rather than a constraint:
--
--   A position with ZERO rows here allows every method the PRODUCT supports,
--   using the position's own area and the product-level max_colors.
--   A position WITH rows allows only those, with these overrides applied.
--
-- This avoids seeding an N x M explosion for the 95% of products where every
-- method works on every position, while keeping a real escape hatch: a mug
-- handle takes pad printing but not sublimation.
--
-- Same "empty means all" convention as spec_def_categories. One convention,
-- used twice, stated once.
create table if not exists public.position_print_methods (
  position_id uuid not null references public.print_positions(id) on delete cascade,
  method_code text not null references public.print_methods(code) on delete cascade,
  area_w_mm   numeric(6,1),
  area_h_mm   numeric(6,1),
  max_colors  int,
  primary key (position_id, method_code)
);

-- ---------------------------------------------------------------- fonts ----

-- A table, not a hardcoded list, so the owner adds an Arabic display font
-- without a deploy. In the individual-gift flow the font IS the product.
create table if not exists public.fonts (
  key         text primary key,
  name_ar     text not null,
  name_en     text,
  css_family  text not null,
  script      text not null default 'arabic' check (script in ('arabic','latin','both')),
  webfont_url text,
  preview_url text,
  is_display  boolean not null default false,
  sort_order  int not null default 0,
  is_active   boolean not null default true
);

-- ## 20260810100003_pricing.sql
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

-- ## 20260810100004_specs.sql
-- ============================================================================
--  كتالوج المواصفات
--
--  The table that makes the add-product form, the spec sheet and the filters
--  data-driven. Renaming a spec, reordering it, hiding it or making it
--  non-filterable is a row edit — no rebuild, no deploy. Adding a genuinely new
--  spec DIMENSION is one `alter table public.products` plus one row here, and
--  the form field, the filter control and the spec row appear on their own.
-- ============================================================================

create table if not exists public.spec_defs (
  key              text primary key,  -- MUST equal a column name on public.products
  label_ar         text not null,
  label_en         text,
  unit_ar          text,
  kind             public.spec_kind not null,
  higher_is_better boolean,           -- null for bool/enum/text
  is_filterable    boolean not null default true,
  show_in_card     boolean not null default false,
  -- Shown in the short form; the rest hide behind "كل المواصفات".
  is_key           boolean not null default false,
  section_ar       text,              -- groups the spec sheet
  sort_order       int not null default 0
);

create table if not exists public.spec_options (
  spec_key   text not null references public.spec_defs(key) on delete cascade,
  value      text not null,
  label_ar   text not null,
  sort_order int not null default 0,
  primary key (spec_key, value)
);

-- ---------------------------------------------------------------------------
--  THE ONE ADAPTATION THE SIBLING PROJECT DID NOT NEED
--
--  The scooter shop had exactly one product type, so every spec applied to
--  every row and an unscoped catalogue was correct. Here there are twelve
--  product types. Unscoped, the add-product form asks for paper_gsm on a
--  powerbank and battery_mah on a notebook — sixty fields, and DECISIONS.md
--  already names that failure mode: the owner opens a form with twenty-six
--  boxes, enters one product, and never comes back.
--
--  CONVENTION: zero rows here = the spec applies to EVERY category. So
--  weight_g and material_ar need no rows at all, and only the specialised ones
--  are scoped. Same "empty means all" rule as position_print_methods — one
--  convention, used twice, stated once.
-- ---------------------------------------------------------------------------
create table if not exists public.spec_def_categories (
  spec_key    text not null references public.spec_defs(key)   on delete cascade,
  category_id uuid not null references public.categories(id)   on delete cascade,
  primary key (spec_key, category_id)
);

-- Resolves the convention above into a straight answer, so the form, the spec
-- sheet and the harness all ask the same question the same way.
create or replace function public.specs_for_category(p_category uuid)
returns setof public.spec_defs
language sql stable as $$
  select d.*
    from public.spec_defs d
   where not exists (select 1 from public.spec_def_categories c where c.spec_key = d.key)
      or exists (
           select 1 from public.spec_def_categories c
            where c.spec_key = d.key and c.category_id = p_category
         )
   order by d.sort_order, d.key
$$;

-- ## 20260810100005_settings.sql
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

-- ## 20260810100006_rls.sql
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

-- ## 20260810100007_storage.sql
-- ============================================================================
--  التخزين — دلوان: صور المنتجات (عام) وملفات العملاء (خاص)
-- ============================================================================

-- صور المنتجات. Public read: it is a shop window, and a signed URL per card in
-- a scrolling grid is a round trip per card.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('product-media', 'product-media', true, 5242880,
        array['image/jpeg','image/png','image/webp','image/avif','image/svg+xml'])
on conflict (id) do nothing;

-- ملفات العملاء — لوجوهات وتصميمات.
--
-- PRIVATE, and that is not a default — it is a decision. A customer's
-- unreleased logo is their property, not a shop window. The admin reads it
-- through a signed URL.
--
-- allowed_mime_types IS DELIBERATELY NULL. Browsers report .ai as
-- application/pdf or as an empty string, .cdr as application/octet-stream, and
-- Safari sometimes sends ''. A strict mime list here rejects genuine artwork
-- and the customer blames the site. The real gate is an EXTENSION + size check
-- in the browser and again in register_upload() (20260810100008).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('customer-artwork', 'customer-artwork', false, 20971520, null)
on conflict (id) do nothing;

-- ---------------------------------------------------------- product media ----

drop policy if exists product_media_read on storage.objects;
create policy product_media_read on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'product-media');

drop policy if exists product_media_write on storage.objects;
create policy product_media_write on storage.objects
  for all to authenticated
  using (bucket_id = 'product-media' and public.is_manager())
  with check (bucket_id = 'product-media' and public.is_manager());

-- -------------------------------------------------------- customer artwork ----

-- The path is customer-artwork/<auth.uid()>/<uuid>.<ext>, and the first folder
-- segment IS the authorisation. Same shape as the avatars policy in the
-- egy-league project, with two deliberate divergences:
--
--   * no public read — see above;
--   * no customer DELETE after submission. The file is evidence of what was
--     agreed, and a customer who deletes their artwork mid-job leaves the
--     workshop holding a job sheet that points at nothing.
--
-- Note this policy alone is not enough: create_order_request() must ALSO
-- verify that each submitted path's first segment equals the caller's uid
-- before inserting order_line_assets. Without that check, anyone can attach
-- anyone else's artwork to their own order. It is the single easiest thing in
-- this system to forget, so the harness asserts it.
drop policy if exists artwork_insert on storage.objects;
create policy artwork_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'customer-artwork'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists artwork_update on storage.objects;
create policy artwork_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'customer-artwork'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- The uploader needs to read back what it just wrote to show a thumbnail.
drop policy if exists artwork_read_own on storage.objects;
create policy artwork_read_own on storage.objects
  for select to authenticated
  using (
    bucket_id = 'customer-artwork'
    and ((storage.foldername(name))[1] = auth.uid()::text or public.is_manager())
  );

drop policy if exists artwork_manager_delete on storage.objects;
create policy artwork_manager_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'customer-artwork' and public.is_manager());

-- ## 20260810100008_quote.sql
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

-- ## 20260810100009_orders.sql
-- ============================================================================
--  الطلبات — التسجيل وآلة الحالات
--
--  ⚠  Sorts AFTER 20260810100006_rls.sql. Carries its own grants, at the bottom.
--
--  Modelled on the sibling project's buy_requests, and the four rules that made
--  it work carry over unchanged:
--    1. SNAPSHOTS, not joins. Repricing a mug next year must not rewrite an
--       order placed this year.
--    2. A code a human can say on the phone, from a sequence.
--    3. Rate limiting INSIDE the security-definer function. The anon key is in
--       the JavaScript bundle; the app is not the gate.
--    4. Status transitions in a FUNCTION, not an UPDATE policy. A policy can
--       say who may write; only a function can say which move is legal.
--
--  These tables have NO anon grant of any kind. Everything a visitor can do
--  goes through the three RPCs granted at the bottom.
-- ============================================================================

do $$ begin create type public.customer_kind as enum ('company','individual');
exception when duplicate_object then null; end $$;

-- The artwork loop is where every print job actually lives, so it is a status.
-- The owner's daily question is "which jobs are waiting on the customer to
-- approve the proof?" and a boolean cannot answer it.
--
-- The DEPOSIT is deliberately NOT here. It can land at several points in the
-- sequence, and encoding it as a status would force a false ordering; it is a
-- boolean plus an amount on the row.
do $$ begin create type public.order_status as enum (
  'new','contacted','quoted','artwork_review','artwork_approved',
  'in_production','ready','delivered','cancelled');
exception when duplicate_object then null; end $$;

do $$ begin create type public.asset_kind as enum ('logo','reference','proof');
exception when duplicate_object then null; end $$;

create sequence if not exists public.order_code_seq start 1001;

-- ---------------------------------------------------------------------------
--  Uploads, recorded.
--
--  Storage RLS already stops a customer writing outside their own folder. This
--  table is the second half: an upload that was never REGISTERED can never be
--  attached to an order, so a direct write to storage that skips the app buys
--  nothing. It is also where the per-uid ceiling lives, because storage
--  policies cannot count.
-- ---------------------------------------------------------------------------
create table if not exists public.customer_uploads (
  id            uuid primary key default gen_random_uuid(),
  storage_path  text not null unique,
  owner_id      uuid not null,
  original_name text,
  mime          text,
  bytes         bigint,
  px_width      int,
  px_height     int,
  created_at    timestamptz not null default now()
);

create index if not exists customer_uploads_owner_idx
  on public.customer_uploads(owner_id, created_at desc);

-- ---------------------------------------------------------------------------
--  The order.
-- ---------------------------------------------------------------------------
create table if not exists public.order_requests (
  id   uuid primary key default gen_random_uuid(),
  code text not null unique
       default 'NC-' || lpad(nextval('public.order_code_seq')::text, 5, '0'),

  customer_kind public.customer_kind not null,
  contact_name  text not null,
  contact_phone text not null,            -- normalised, 01XXXXXXXXX
  contact_email text,
  company_name  text,
  tax_id        text,                     -- corporates need a tax invoice
  governorate   text,
  area          text,
  address       text,

  needed_by date,                         -- the most useful field after the phone

  -- "أقر بأن لي حق استخدام الشعار". The site receives other companies'
  -- trademarks; this is the one line that says who asked for that.
  ip_confirmed      boolean not null,
  -- SEPARATE from the above on purpose: using a client's logo in your own
  -- portfolio without permission is a different act, and a different consent.
  portfolio_consent boolean not null default false,

  -- Every figure below is the SERVER's, computed by price_quote() at submit
  -- time. client_total is what the browser showed, kept only so a mismatch can
  -- be seen rather than argued about.
  subtotal            numeric(12,2) not null default 0,
  setup_total         numeric(12,2) not null default 0,
  vat_rate_at_request numeric(5,4)  not null default 0,
  vat_amount          numeric(12,2) not null default 0,
  total               numeric(12,2) not null default 0,
  client_total        numeric(12,2),
  price_mismatch      boolean not null default false,

  deposit_amount   numeric(12,2),
  deposit_received boolean not null default false,

  status        public.order_status not null default 'new',
  manager_note  text,
  cancel_reason text,
  customer_note text,
  source        text,
  is_spam       boolean not null default false,

  whatsapp_sent_at timestamptz,
  created_at   timestamptz not null default now(),
  contacted_at timestamptz,
  closed_at    timestamptz
);

create index if not exists order_requests_status_idx on public.order_requests(status, created_at desc);
create index if not exists order_requests_phone_idx  on public.order_requests(contact_phone, created_at desc);
create index if not exists order_requests_needed_idx on public.order_requests(needed_by)
  where status not in ('delivered','cancelled');

-- ---------------------------------------------------------------------------
--  Lines and their children.
--
--  Relational children rather than one payload jsonb, deliberately: the owner
--  will want "how many navy t-shirts did we do in Q1", and the workshop's job
--  sheet has to read the text EXACTLY as the customer typed it. A blob answers
--  neither. The snapshot labels live inside the child rows so renaming an
--  option next year cannot rewrite an old job sheet.
-- ---------------------------------------------------------------------------
create table if not exists public.order_request_lines (
  id         uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.order_requests(id) on delete cascade,
  line_no    int not null,

  product_id uuid references public.products(id) on delete set null,
  product_name_ar  text not null,
  product_slug     text,
  cover_url        text,
  category_name_ar text,

  qty            int not null check (qty >= 1),
  moq_at_request int,

  method_code    text,
  method_name_ar text,
  colors_count   int,
  -- The screen is RGB and the print is Pantone. The swatch is never a promise;
  -- this column is where the promise actually lives.
  pantone_codes  text[],

  setup_fee_at_request  numeric(10,2) not null default 0,
  unit_price_at_request numeric(10,2) not null default 0,
  options_delta         numeric(10,2) not null default 0,
  method_addon          numeric(10,2) not null default 0,
  line_subtotal         numeric(12,2) not null default 0,
  line_total            numeric(12,2) not null default 0,

  is_gift_wrap boolean not null default false,
  gift_message text,
  notes        text,

  unique (request_id, line_no)
);

create table if not exists public.order_line_positions (
  line_id          uuid not null references public.order_request_lines(id) on delete cascade,
  position_id      uuid references public.print_positions(id) on delete set null,
  position_name_ar text not null,
  area_w_mm        numeric(6,1),
  area_h_mm        numeric(6,1),
  setup_fee_applied numeric(10,2) not null default 0,
  primary key (line_id, position_name_ar)
);

create table if not exists public.order_line_options (
  line_id        uuid not null references public.order_request_lines(id) on delete cascade,
  group_code     text not null,
  group_label_ar text not null,
  item_value     text not null,
  item_label_ar  text not null,
  hex            text,
  price_delta    numeric(10,2) not null default 0,
  primary key (line_id, group_code)
);

create table if not exists public.order_line_texts (
  line_id      uuid not null references public.order_request_lines(id) on delete cascade,
  slot         int not null,
  content      text not null,
  font_key     text,
  font_name_ar text,
  color_hex    text,
  pantone_code text,
  primary key (line_id, slot)
);

create table if not exists public.order_line_assets (
  id            uuid primary key default gen_random_uuid(),
  line_id       uuid not null references public.order_request_lines(id) on delete cascade,
  upload_id     uuid references public.customer_uploads(id) on delete set null,
  storage_path  text not null,
  original_name text,
  mime          text,
  bytes         bigint,
  kind          public.asset_kind not null default 'logo',
  uploaded_by   uuid,
  px_width      int,
  px_height     int,
  -- Effective resolution at the printed size, computed in the browser from the
  -- image and the position's area. Stored so the admin sees the same number the
  -- customer was warned about.
  dpi_at_position numeric(6,1),
  created_at    timestamptz not null default now()
);

create index if not exists order_lines_parent_idx  on public.order_request_lines(request_id);
create index if not exists order_assets_parent_idx on public.order_line_assets(line_id);

create table if not exists public.order_request_events (
  id          uuid primary key default gen_random_uuid(),
  request_id  uuid not null references public.order_requests(id) on delete cascade,
  actor_id    uuid,
  from_status public.order_status,
  to_status   public.order_status,
  note        text,
  created_at  timestamptz not null default now()
);

create index if not exists order_events_parent_idx
  on public.order_request_events(request_id, created_at);

create or replace function public.order_status_event()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into public.order_request_events (request_id, to_status, note)
    values (new.id, new.status, 'الطلب وصل');
  elsif old.status is distinct from new.status then
    insert into public.order_request_events (request_id, actor_id, from_status, to_status, note)
    values (new.id, auth.uid(), old.status, new.status,
            coalesce(new.cancel_reason, new.manager_note));
  end if;
  return null;
end $$;

drop trigger if exists order_requests_event on public.order_requests;
create trigger order_requests_event
  after insert or update of status on public.order_requests
  for each row execute function public.order_status_event();

-- ---------------------------------------------------------------------------
--  RLS. No anon grant at all — a visitor never touches these tables directly.
-- ---------------------------------------------------------------------------
alter table public.customer_uploads      enable row level security;
alter table public.order_requests        enable row level security;
alter table public.order_request_lines   enable row level security;
alter table public.order_line_positions  enable row level security;
alter table public.order_line_options    enable row level security;
alter table public.order_line_texts      enable row level security;
alter table public.order_line_assets     enable row level security;
alter table public.order_request_events  enable row level security;

revoke all on
  public.customer_uploads, public.order_requests, public.order_request_lines,
  public.order_line_positions, public.order_line_options, public.order_line_texts,
  public.order_line_assets, public.order_request_events
from anon;

do $$
declare t text;
begin
  foreach t in array array[
    'order_requests','order_request_lines','order_line_positions',
    'order_line_options','order_line_texts','order_line_assets',
    'order_request_events','customer_uploads'
  ] loop
    execute format('drop policy if exists %I_manager on public.%I', t, t);
    execute format(
      'create policy %I_manager on public.%I for all to authenticated
         using (public.is_manager()) with check (public.is_manager())', t, t);
  end loop;
end $$;

-- The one exception: an anonymous uploader may see the rows it registered, so
-- the uploader can show a thumbnail list without a round trip through an RPC.
drop policy if exists customer_uploads_own on public.customer_uploads;
create policy customer_uploads_own on public.customer_uploads
  for select to authenticated using (owner_id = auth.uid());

-- ---------------------------------------------------------------------------
--  THE STATUS COLUMN IS NOT WRITABLE BY ANYONE, INCLUDING A MANAGER.
--
--  The manager policy above says `for all`, which would let the admin panel
--  write `status = 'delivered'` straight onto a brand-new order and skip every
--  transition rule in set_order_status(). A rule you can go around is a
--  suggestion.
--
--  So the privilege is taken at the COLUMN level — the same shape as the
--  profiles.role lock — and set_order_status() reaches it anyway because it is
--  SECURITY DEFINER and runs as the owner. The panel keeps the fields a human
--  genuinely edits by hand.
-- ---------------------------------------------------------------------------
revoke update on public.order_requests from authenticated;
grant update (
  manager_note, deposit_amount, deposit_received, is_spam,
  needed_by, contact_email, area, address
) on public.order_requests to authenticated;

-- ---------------------------------------------------------------------------
--  register_upload()
--
--  Called after the browser has written the object to storage. Validates by
--  EXTENSION, not by mime: browsers report .ai as application/pdf or as an
--  empty string, .cdr as application/octet-stream, and Safari sometimes sends
--  ''. A strict mime check rejects genuine artwork and the customer blames the
--  site.
-- ---------------------------------------------------------------------------
create or replace function public.register_upload(
  p_path text, p_original_name text, p_mime text, p_bytes bigint,
  p_px_width int default null, p_px_height int default null
) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid uuid := auth.uid();
  v_ext text;
  v_recent int;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'NOT_SIGNED_IN' using hint = 'محتاج جلسة قبل رفع الملف';
  end if;

  -- The first path segment IS the authorisation, matching the storage policy.
  if (storage.foldername(p_path))[1] is distinct from v_uid::text then
    raise exception 'ASSET_NOT_YOURS' using hint = 'مسار الملف مش تبع الجلسة دي';
  end if;

  v_ext := lower(regexp_replace(p_path, '^.*\.', ''));
  if v_ext not in ('ai','pdf','eps','svg','png','jpg','jpeg','webp','cdr','zip') then
    raise exception 'FILE_TYPE_NOT_ALLOWED' using hint = 'الصيغة دي مش مدعومة';
  end if;

  if p_bytes is not null and p_bytes > 20971520 then
    raise exception 'FILE_TOO_LARGE' using hint = 'أقصى حجم ٢٠ ميجا';
  end if;

  -- The ceiling storage policies cannot express. Generous for a real customer
  -- with a dozen artworks, useless for a script.
  select count(*) into v_recent
    from public.customer_uploads
   where owner_id = v_uid and created_at > now() - interval '1 day';
  if v_recent >= 40 then
    raise exception 'UPLOAD_LIMIT' using hint = 'رفعت ملفات كتير النهارده';
  end if;

  insert into public.customer_uploads
    (storage_path, owner_id, original_name, mime, bytes, px_width, px_height)
  values (p_path, v_uid, p_original_name, p_mime, p_bytes, p_px_width, p_px_height)
  on conflict (storage_path) do update
    set original_name = excluded.original_name
  returning id into v_id;

  return v_id;
end $$;

-- ---------------------------------------------------------------------------
--  create_order_request()
--
--  The whole submission, in one call. Takes jsonb because the number of lines
--  is not known in advance and a variadic signature would be worse.
--
--  It RECOMPUTES every price with price_quote() and stores its own numbers.
--  Whatever total the browser sends is recorded next to them and ignored.
-- ---------------------------------------------------------------------------
create or replace function public.create_order_request(p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid   uuid := auth.uid();
  v_phone text := public.normalize_phone(p_payload ->> 'contact_phone');
  v_recent int;
  v_global int;
  v_id   uuid;
  v_code text;
  v_line jsonb;
  v_line_id uuid;
  v_no int := 0;
  v_q jsonb;
  v_product record;
  v_method record;
  v_pos jsonb;
  v_opt jsonb;
  v_txt jsonb;
  v_asset text;
  v_upload record;
  v_position_ids uuid[];
  v_option_ids uuid[];
  v_subtotal numeric(12,2) := 0;
  v_setup numeric(12,2) := 0;
  v_vat_rate numeric(5,4);
  v_inclusive boolean;
  v_pre_vat numeric(12,2);
  v_vat numeric(12,2);
  v_client_total numeric(12,2);
begin
  -- ---- who ---------------------------------------------------------------
  if coalesce(p_payload ->> 'contact_name', '') = '' then
    raise exception 'NAME_REQUIRED' using hint = 'الاسم مطلوب';
  end if;
  if not public.is_eg_mobile(v_phone) then
    raise exception 'PHONE_INVALID' using hint = 'رقم موبايل مصري غير صحيح';
  end if;
  if coalesce((p_payload ->> 'ip_confirmed')::boolean, false) is not true then
    raise exception 'IP_NOT_CONFIRMED'
      using hint = 'لازم تأكيد إن لك حق استخدام الشعار';
  end if;
  if jsonb_array_length(coalesce(p_payload -> 'lines', '[]'::jsonb)) = 0 then
    raise exception 'NO_LINES' using hint = 'مفيش منتجات في الطلب';
  end if;

  -- ---- the flood gates ----------------------------------------------------
  -- Inside the function, not in the app: the anon key ships in the bundle, so
  -- anything enforced in JavaScript is enforced nowhere.
  select count(*) into v_recent from public.order_requests
   where contact_phone = v_phone and created_at > now() - interval '1 hour';
  if v_recent >= 3 then
    raise exception 'RATE_LIMITED'
      using hint = 'بعتّ ٣ طلبات في آخر ساعة — كلمنا على واتساب';
  end if;

  select count(*) into v_global from public.order_requests
   where created_at > now() - interval '1 minute';
  if v_global >= 20 then
    raise exception 'RATE_LIMITED' using hint = 'ضغط عالي دلوقتي، جرّب بعد شوية';
  end if;

  select s.vat_rate, s.prices_include_vat into v_vat_rate, v_inclusive
    from public.site_settings s where s.id;
  v_vat_rate := coalesce(v_vat_rate, 0);

  insert into public.order_requests (
    customer_kind, contact_name, contact_phone, contact_email,
    company_name, tax_id, governorate, area, address, needed_by,
    ip_confirmed, portfolio_consent, customer_note, source,
    vat_rate_at_request
  ) values (
    coalesce((p_payload ->> 'customer_kind')::public.customer_kind, 'individual'),
    p_payload ->> 'contact_name',
    v_phone,
    nullif(p_payload ->> 'contact_email', ''),
    nullif(p_payload ->> 'company_name', ''),
    nullif(p_payload ->> 'tax_id', ''),
    nullif(p_payload ->> 'governorate', ''),
    nullif(p_payload ->> 'area', ''),
    nullif(p_payload ->> 'address', ''),
    nullif(p_payload ->> 'needed_by', '')::date,
    true,
    coalesce((p_payload ->> 'portfolio_consent')::boolean, false),
    nullif(p_payload ->> 'note', ''),
    coalesce(nullif(p_payload ->> 'source', ''), 'quote'),
    v_vat_rate
  ) returning id, code into v_id, v_code;

  -- ---- the lines ----------------------------------------------------------
  for v_line in select * from jsonb_array_elements(p_payload -> 'lines') loop
    v_no := v_no + 1;

    select p.*, c.name_ar as category_name_ar into v_product
      from public.products p
      left join public.categories c on c.id = p.category_id
     where p.id = (v_line ->> 'product_id')::uuid and p.is_published;

    if not found then
      raise exception 'PRODUCT_NOT_FOUND' using hint = 'منتج مش موجود أو مش منشور';
    end if;

    select array(select jsonb_array_elements_text(coalesce(v_line -> 'position_ids', '[]'::jsonb))::uuid)
      into v_position_ids;
    select array(select jsonb_array_elements_text(coalesce(v_line -> 'option_item_ids', '[]'::jsonb))::uuid)
      into v_option_ids;

    -- THE AUTHORITY. Whatever the browser computed is irrelevant here.
    v_q := public.price_quote(
      v_product.id,
      (v_line ->> 'qty')::int,
      nullif(v_line ->> 'method_code', ''),
      coalesce((v_line ->> 'colors')::int, 1),
      v_position_ids,
      v_option_ids
    );

    if (v_q ->> 'ok')::boolean is not true then
      raise exception 'LINE_INVALID: %', v_q ->> 'errors'
        using hint = 'في سطر اختياراته مش مظبوطة — حدّث الصفحة وجرّب تاني';
    end if;

    select pm.*, m.name_ar as method_name_ar into v_method
      from public.product_print_methods pm
      join public.print_methods m on m.code = pm.method_code
     where pm.product_id = v_product.id
       and pm.method_code = nullif(v_line ->> 'method_code', '');

    insert into public.order_request_lines (
      request_id, line_no, product_id, product_name_ar, product_slug, cover_url,
      category_name_ar, qty, moq_at_request, method_code, method_name_ar,
      colors_count, setup_fee_at_request, unit_price_at_request, options_delta,
      method_addon, line_subtotal, line_total, is_gift_wrap, gift_message, notes
    ) values (
      v_id, v_no, v_product.id, v_product.name_ar, v_product.slug, v_product.cover_url,
      v_product.category_name_ar,
      (v_q ->> 'qty')::int, v_product.moq,
      nullif(v_line ->> 'method_code', ''), v_method.method_name_ar,
      (v_q ->> 'colors')::int,
      (v_q ->> 'setup_total')::numeric,
      (v_q ->> 'unit_price')::numeric,
      (v_q ->> 'options_delta')::numeric,
      (v_q ->> 'method_addon')::numeric,
      (v_q ->> 'subtotal')::numeric,
      (v_q ->> 'subtotal')::numeric + (v_q ->> 'setup_total')::numeric,
      coalesce((v_line ->> 'is_gift_wrap')::boolean, false),
      nullif(v_line ->> 'gift_message', ''),
      nullif(v_line ->> 'notes', '')
    ) returning id into v_line_id;

    v_subtotal := v_subtotal + (v_q ->> 'subtotal')::numeric;
    v_setup    := v_setup    + (v_q ->> 'setup_total')::numeric;

    -- positions, snapshotted with their names
    for v_pos in
      select to_jsonb(pp) from public.print_positions pp
       where pp.id = any(v_position_ids) and pp.product_id = v_product.id
    loop
      insert into public.order_line_positions
        (line_id, position_id, position_name_ar, area_w_mm, area_h_mm, setup_fee_applied)
      values (
        v_line_id, (v_pos ->> 'id')::uuid, v_pos ->> 'name_ar',
        (v_pos ->> 'area_w_mm')::numeric, (v_pos ->> 'area_h_mm')::numeric,
        case when coalesce(array_length(v_position_ids, 1), 0) > 0
             then (v_q ->> 'setup_total')::numeric / array_length(v_position_ids, 1)
             else 0 end
      ) on conflict do nothing;
    end loop;

    for v_opt in
      select jsonb_build_object(
        'group_code', g.code, 'group_label_ar', g.label_ar,
        'item_value', i.value, 'item_label_ar', i.label_ar,
        'hex', i.hex, 'price_delta', i.price_delta)
        from public.product_option_items i
        join public.product_option_groups g on g.id = i.group_id
       where i.id = any(v_option_ids) and g.product_id = v_product.id
    loop
      insert into public.order_line_options
        (line_id, group_code, group_label_ar, item_value, item_label_ar, hex, price_delta)
      values (
        v_line_id, v_opt ->> 'group_code', v_opt ->> 'group_label_ar',
        v_opt ->> 'item_value', v_opt ->> 'item_label_ar',
        v_opt ->> 'hex', (v_opt ->> 'price_delta')::numeric
      ) on conflict do nothing;
    end loop;

    -- the words, exactly as typed
    for v_txt in select * from jsonb_array_elements(coalesce(v_line -> 'texts', '[]'::jsonb)) loop
      if coalesce(v_txt ->> 'content', '') <> '' then
        insert into public.order_line_texts
          (line_id, slot, content, font_key, font_name_ar, color_hex, pantone_code)
        values (
          v_line_id,
          coalesce((v_txt ->> 'slot')::int, 1),
          v_txt ->> 'content',
          nullif(v_txt ->> 'font_key', ''),
          (select f.name_ar from public.fonts f where f.key = v_txt ->> 'font_key'),
          nullif(v_txt ->> 'color_hex', ''),
          nullif(v_txt ->> 'pantone_code', '')
        ) on conflict (line_id, slot) do nothing;
      end if;
    end loop;

    -- ---- the artwork. THE CHECK THAT IS EASIEST TO FORGET ----------------
    --
    -- Without verifying that the first path segment is the CALLER's uid, any
    -- visitor could attach any other customer's logo to their own order simply
    -- by guessing a path. The storage policy stops them WRITING there; only
    -- this stops them CLAIMING it.
    for v_asset in
      select jsonb_array_elements_text(coalesce(v_line -> 'asset_paths', '[]'::jsonb))
    loop
      if (storage.foldername(v_asset))[1] is distinct from v_uid::text then
        raise exception 'ASSET_NOT_YOURS' using hint = 'ملف مش تبع الجلسة دي';
      end if;

      select * into v_upload from public.customer_uploads
       where storage_path = v_asset and owner_id = v_uid;
      if not found then
        raise exception 'ASSET_NOT_REGISTERED' using hint = 'الملف ده مش مسجّل';
      end if;

      insert into public.order_line_assets (
        line_id, upload_id, storage_path, original_name, mime, bytes,
        kind, uploaded_by, px_width, px_height, dpi_at_position
      ) values (
        v_line_id, v_upload.id, v_upload.storage_path, v_upload.original_name,
        v_upload.mime, v_upload.bytes, 'logo', v_uid,
        v_upload.px_width, v_upload.px_height,
        nullif(v_line ->> 'dpi_at_position', '')::numeric
      );
    end loop;
  end loop;

  -- ---- the totals, server-side ------------------------------------------
  v_pre_vat := v_subtotal + v_setup;
  v_vat := case when v_inclusive then 0 else round(v_pre_vat * v_vat_rate, 2) end;
  v_client_total := nullif(p_payload ->> 'client_total', '')::numeric;

  update public.order_requests set
    subtotal = v_subtotal,
    setup_total = v_setup,
    vat_amount = v_vat,
    total = v_pre_vat + v_vat,
    client_total = v_client_total,
    -- A mismatch does NOT reject the order. Rejecting punishes a customer who
    -- left a tab open across a price change; flagging tells the owner to
    -- mention it on the call. One piastre of tolerance for rounding.
    price_mismatch = v_client_total is not null
                     and abs(v_client_total - (v_pre_vat + v_vat)) > 0.01
  where id = v_id;

  return jsonb_build_object(
    'id', v_id,
    'code', v_code,
    'total', v_pre_vat + v_vat,
    'subtotal', v_subtotal,
    'setup_total', v_setup,
    'vat_amount', v_vat
  );
end $$;

-- ---------------------------------------------------------------------------
--  order_status() — tracking with no account.
--
--  Needs BOTH the id (stored on the customer's device) and the matching phone.
--  Either alone is a way to read somebody else's order: ids leak through
--  browser history, and phone numbers are guessable.
-- ---------------------------------------------------------------------------
create or replace function public.order_status(p_id uuid, p_phone text)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'code', o.code,
    'status', o.status,
    'total', o.total,
    'created_at', o.created_at,
    'needed_by', o.needed_by,
    'deposit_received', o.deposit_received,
    'lines', coalesce((
      select jsonb_agg(jsonb_build_object(
        'product_name_ar', l.product_name_ar,
        'qty', l.qty,
        'method_name_ar', l.method_name_ar,
        'line_total', l.line_total) order by l.line_no)
        from public.order_request_lines l where l.request_id = o.id), '[]'::jsonb)
  )
    from public.order_requests o
   where o.id = p_id
     and o.contact_phone = public.normalize_phone(p_phone)
$$;

-- ---------------------------------------------------------------------------
--  set_order_status() — the machine.
--
--  In a function, not an UPDATE policy: a policy can say WHO may write, only a
--  function can say which MOVE is legal. delivered and cancelled are dead ends;
--  cancelling without a reason is refused, because "why did this not happen?"
--  is the question somebody always asks three months later.
-- ---------------------------------------------------------------------------
create or replace function public.set_order_status(
  p_id uuid, p_status public.order_status, p_note text default null,
  p_reason text default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_from public.order_status;
  v_allowed public.order_status[];
begin
  if not public.is_manager() then
    raise exception 'NOT_AUTHORISED';
  end if;

  select status into v_from from public.order_requests where id = p_id;
  if v_from is null then raise exception 'ORDER_NOT_FOUND'; end if;

  if v_from in ('delivered','cancelled') then
    raise exception 'STATUS_FINAL' using hint = 'الطلب في حالة نهائية';
  end if;

  v_allowed := case v_from
    when 'new'              then array['contacted','cancelled']
    when 'contacted'        then array['quoted','cancelled']
    when 'quoted'           then array['artwork_review','cancelled']
    when 'artwork_review'   then array['artwork_approved','quoted','cancelled']
    when 'artwork_approved' then array['in_production','cancelled']
    when 'in_production'    then array['ready','cancelled']
    when 'ready'            then array['delivered','cancelled']
  end::public.order_status[];

  if not (p_status = any(v_allowed)) then
    raise exception 'STATUS_TRANSITION_NOT_ALLOWED: % -> %', v_from, p_status;
  end if;

  if p_status = 'cancelled' and coalesce(p_reason, '') = '' then
    raise exception 'CANCEL_REASON_REQUIRED' using hint = 'لازم سبب الإلغاء';
  end if;

  update public.order_requests set
    status = p_status,
    manager_note = coalesce(p_note, manager_note),
    cancel_reason = case when p_status = 'cancelled' then p_reason else cancel_reason end,
    contacted_at = case when p_status = 'contacted' then now() else contacted_at end,
    closed_at = case when p_status in ('delivered','cancelled') then now() else closed_at end
  where id = p_id;
end $$;

-- ---------------------------------------------------------------------------
--  Marks that the customer reached the WhatsApp handoff. Not proof they sent
--  it — nothing can be — but it separates "filled the form and vanished" from
--  "filled the form and opened the chat", which are different follow-ups.
-- ---------------------------------------------------------------------------
create or replace function public.mark_whatsapp_sent(p_id uuid, p_phone text)
returns void
language sql security definer set search_path = public as $$
  update public.order_requests set whatsapp_sent_at = now()
   where id = p_id and contact_phone = public.normalize_phone(p_phone)
     and whatsapp_sent_at is null
$$;

-- ------------------------------------------------------------ الصلاحيات ----

-- Revoke from PUBLIC first. These functions were created after
-- 20260810100006_rls.sql, so they still carry the default PUBLIC grant that
-- makes a `revoke ... from anon` a no-op.
revoke execute on function public.order_status_event()                              from public, anon;
revoke execute on function public.register_upload(text, text, text, bigint, int, int) from public, anon;
revoke execute on function public.create_order_request(jsonb)                       from public, anon;
revoke execute on function public.order_status(uuid, text)                          from public, anon;
revoke execute on function public.mark_whatsapp_sent(uuid, text)                    from public, anon;
revoke execute on function public.set_order_status(uuid, public.order_status, text, text)
  from public, anon;

-- A visitor orders without an account, so these four are open. Every one of
-- them carries its own gate inside: register_upload checks the path belongs to
-- the caller, create_order_request rate-limits and re-prices, and the two
-- read-backs need the id AND the matching phone.
grant execute on function public.register_upload(text, text, text, bigint, int, int)
  to anon, authenticated;
grant execute on function public.create_order_request(jsonb)    to anon, authenticated;
grant execute on function public.order_status(uuid, text)       to anon, authenticated;
grant execute on function public.mark_whatsapp_sent(uuid, text) to anon, authenticated;

-- Manager only. The is_manager() check inside is the belt; this grant is the
-- braces.
grant execute on function public.set_order_status(uuid, public.order_status, text, text)
  to authenticated;

-- ## 20260810100010_cleanup.sql
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

-- ## 20260810100011_accounts.sql
-- ============================================================================
--  الحسابات — دخول الإدارة
--
--  ⚠  Sorts AFTER 20260810100006_rls.sql. Carries its own revokes and grants.
--
--  Only staff sign in. Customers browse, configure, upload artwork and file
--  orders with no account at all — that is the whole design, and this file
--  exists to give the shop's own people a door.
--
--  Ported from the sibling project, including three traps that cost real time
--  there and are commented where they bite.
-- ============================================================================

-- The phone → synthetic email bridge. Supabase's real phone auth bills per SMS
-- through a third party, and a shop with four staff does not need it: the
-- number is the username, the address is derived, and nobody ever reads that
-- mailbox.
create or replace function public.email_for_phone(p_phone text)
returns text
language sql immutable as $$
  select public.normalize_phone(p_phone) || '@staff.nextcampaign.app'
$$;

-- ---------------------------------------------------------------------------
--  TRAP 1. GoTrue reads several token columns as NOT NULL even though the
--  schema allows nulls. A row inserted directly into auth.users leaves them
--  null and sign-in then fails with "Database error querying schema" — an
--  error that says nothing about the actual cause.
--
--  The loop is guarded per column so this keeps working on a Supabase release
--  with a different column set, rather than failing on a column that no longer
--  exists.
-- ---------------------------------------------------------------------------
drop function if exists public.fix_auth_user_tokens(uuid);

create or replace function public.fix_auth_user_tokens(p_id uuid)
returns void
language plpgsql security definer set search_path = public, auth as $$
declare c text;
begin
  foreach c in array array[
    'confirmation_token','recovery_token','email_change',
    'email_change_token_new','email_change_token_current',
    'phone_change','phone_change_token','reauthentication_token'
  ] loop
    begin
      execute format(
        'update auth.users set %I = coalesce(%I, %L) where id = $1', c, c, ''
      ) using p_id;
    exception when undefined_column then null;
    end;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
--  The private body. Creates a real Supabase Auth user from a phone number.
--
--  TRAP 2. auth.signUp is deliberately NOT used: it waits on a confirmation
--  e-mail to a mailbox that does not exist, because the address is synthetic.
--
--  TRAP 3. `set search_path = public, extensions` IS LOAD-BEARING. On hosted
--  Supabase, crypt() and gen_salt() live in `extensions`, not `public`.
--  Omitting it produces "function gen_salt(unknown) does not exist" on the live
--  database while every local test passes.
-- ---------------------------------------------------------------------------
create or replace function public.create_account(
  p_phone     text,
  p_full_name text,
  p_password  text,
  p_role      public.user_role
) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id    uuid := gen_random_uuid();
  v_phone text := public.normalize_phone(p_phone);
  v_email text;
  v_name  text := nullif(trim(coalesce(p_full_name, '')), '');
begin
  if v_phone is null or not public.is_eg_mobile(v_phone) then
    raise exception 'BAD_PHONE' using errcode = 'P0001';
  end if;
  if v_name is null then
    raise exception 'NAME_REQUIRED' using errcode = 'P0001';
  end if;
  if length(coalesce(p_password, '')) < 6 then
    raise exception 'PASSWORD_TOO_SHORT' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.profiles where phone = v_phone) then
    raise exception 'PHONE_TAKEN' using errcode = 'P0001';
  end if;

  v_email := public.email_for_phone(v_phone);

  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data
  ) values (
    v_id, '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', v_email,
    crypt(p_password, gen_salt('bf')),
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('full_name', v_name, 'phone', v_phone,
                       'role', p_role::text)
  );

  -- GoTrue looks the identity up before the user; without this row sign-in
  -- fails even though the user exists.
  begin
    insert into auth.identities (
      id, provider_id, user_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    ) values (
      gen_random_uuid(), v_id, v_id,
      jsonb_build_object('sub', v_id::text, 'email', v_email,
                         'email_verified', true),
      'email', now(), now(), now()
    );
  exception when others then null;  -- older schemas without provider_id
  end;

  perform public.fix_auth_user_tokens(v_id);

  -- The on_auth_user_created trigger has already mirrored the profile; this
  -- only matters if the trigger is ever removed.
  insert into public.profiles (id, role, full_name, phone)
  values (v_id, p_role, v_name, v_phone)
  on conflict (id) do update
    set role = excluded.role, full_name = excluded.full_name;

  return v_id;
end $$;

-- Nobody may call the private body directly — it takes the ROLE as an
-- argument, so a grant here would be a way for a visitor to mint a manager.
revoke execute on function
  public.create_account(text, text, text, public.user_role)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
--  The manager's door.
-- ---------------------------------------------------------------------------
create or replace function public.admin_create_user(
  p_phone     text,
  p_full_name text,
  p_role      public.user_role,
  p_password  text
) returns uuid
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_manager() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  return public.create_account(p_phone, p_full_name, p_password, p_role);
end $$;

create or replace function public.admin_set_password(p_id uuid, p_password text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  -- Either a manager resetting somebody's password, or a person changing their
  -- own. Both are legitimate; nothing else is.
  if not (public.is_manager() or p_id = auth.uid()) then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if length(coalesce(p_password, '')) < 6 then
    raise exception 'PASSWORD_TOO_SHORT' using errcode = 'P0001';
  end if;

  update auth.users
     set encrypted_password = crypt(p_password, gen_salt('bf')),
         updated_at = now()
   where id = p_id;

  perform public.fix_auth_user_tokens(p_id);
end $$;

create or replace function public.admin_set_active(p_id uuid, p_active boolean)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_manager() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  -- Switching yourself off locks the shop out of its own admin panel.
  if p_id = auth.uid() then
    raise exception 'CANNOT_DISABLE_SELF' using errcode = 'P0001';
  end if;
  if not p_active and (
       select count(*) from public.profiles
        where role = 'manager' and is_active and id <> p_id
     ) = 0 then
    raise exception 'LAST_MANAGER' using errcode = 'P0001';
  end if;

  update public.profiles set is_active = p_active where id = p_id;
end $$;

create or replace function public.admin_staff()
returns table (id uuid, full_name text, phone text, role public.user_role,
               is_active boolean, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select p.id, p.full_name, p.phone, p.role, p.is_active, p.created_at
    from public.profiles p
   where public.is_manager() and p.phone is not null
   order by p.created_at
$$;

-- ---------------------------------------------------------------------------
--  Deleting a product.
--
--  Refused once a customer has ordered it. The order line snapshots the name
--  and the price, so the paperwork survives — but the row is still the only
--  link back to what was actually sold, and "how many of these have we done?"
--  stops being answerable the moment it goes.
--
--  Unpublishing is what the owner actually wants in that case, and the panel
--  says so.
-- ---------------------------------------------------------------------------
create or replace function public.admin_delete_product(p_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_manager() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.order_request_lines where product_id = p_id) then
    raise exception 'HAS_HISTORY' using errcode = 'P0001';
  end if;
  delete from public.products where id = p_id;
end $$;

-- ---------------------------------------------------------------------------
--  A signed URL is the only way to read customer artwork: the bucket is
--  private, and it stays private. This wraps the check so the panel does not
--  have to hold a service key to show the owner a logo.
-- ---------------------------------------------------------------------------
create or replace function public.admin_dashboard()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.is_manager() then null else jsonb_build_object(
    'new',            (select count(*) from public.order_requests where status = 'new'),
    'awaiting_proof', (select count(*) from public.order_requests where status = 'artwork_review'),
    'in_production',  (select count(*) from public.order_requests
                        where status in ('artwork_approved','in_production')),
    'urgent',         (select count(*) from public.order_requests
                        where needed_by is not null
                          and needed_by <= current_date + 7
                          and status not in ('delivered','cancelled')),
    'mismatch',       (select count(*) from public.order_requests where price_mismatch),
    'drafts',         (select count(*) from public.products where not is_published),
    'no_cover',       (select count(*) from public.products
                        where is_published and cover_url is null)
  ) end
$$;

-- ---------------------------------------------------------------- grants ---

revoke execute on function public.email_for_phone(text)                              from public, anon;
revoke execute on function public.fix_auth_user_tokens(uuid)                         from public, anon, authenticated;
revoke execute on function public.admin_create_user(text, text, public.user_role, text) from public, anon;
revoke execute on function public.admin_set_password(uuid, text)                     from public, anon;
revoke execute on function public.admin_set_active(uuid, boolean)                    from public, anon;
revoke execute on function public.admin_delete_product(uuid)                         from public, anon;
revoke execute on function public.admin_staff()                                      from public, anon;
revoke execute on function public.admin_dashboard()                                  from public, anon;

-- The login screen turns a phone into the synthetic address before calling
-- signInWithPassword, so anon needs this one.
grant execute on function public.email_for_phone(text) to anon, authenticated;

grant execute on function public.admin_create_user(text, text, public.user_role, text) to authenticated;
grant execute on function public.admin_set_password(uuid, text)  to authenticated;
grant execute on function public.admin_set_active(uuid, boolean) to authenticated;
grant execute on function public.admin_delete_product(uuid)      to authenticated;
grant execute on function public.admin_staff()                   to authenticated;
grant execute on function public.admin_dashboard()               to authenticated;

-- ============================================================================
--  أول حساب مدير
--
--  الموبايل 01000000000 وكلمة السر تحت.
--  ⚠  غيّر كلمة السر أول ما تدخل — الملف ده موجود في المستودع، فأي حد يقراه
--     يعرف كلمة السر دي.
--
--  Re-runnable: a second run finds a manager already there and does nothing.
-- ============================================================================
do $$
begin
  if not exists (select 1 from public.profiles where role = 'manager') then
    perform public.create_account('01000000000', 'المدير', 'campaign2026', 'manager');
  end if;
end $$;

-- ## 20260812100000_clinic_schema.sql
-- ============================================================================
--  العيادة — الـ schema والجداول
--
--  ⚠  Sorts AFTER 20260810100006_rls.sql. Carries its own grants, in
--     20260812100001_clinic_rls.sql. See the rule in tools/build-setup.mjs.
--
--  WHY A SEPARATE SCHEMA AND NOT A `clinic_` PREFIX IN public
--
--  20260810100006_rls.sql hands `anon` SELECT on the shop window by name, and
--  that list is edited by hand every time a catalogue table is added. Patient
--  diagnoses living one careless `grant select` away from that list is not a
--  risk worth carrying. A separate schema makes the mistake IMPOSSIBLE rather
--  than merely unlikely: `anon` has no USAGE on `clinic`, so no grant inside it
--  can be reached at all.
--
--  It also means the day this clinic wants its own Supabase project, moving it
--  is one `pg_dump -n clinic` rather than an archaeology dig through public.
--
--  ONE EXTRA SETUP STEP, and it is documented in docs/ابدأ-من-هنا.md:
--    Supabase dashboard → Settings → API → Exposed schemas → add `clinic`
--  Without it PostgREST cannot see these tables and the app shows an empty
--  clinic with no error worth reading.
-- ============================================================================

create schema if not exists clinic;

-- Nothing anonymous, ever. Not a policy — a missing USAGE, which is a wall
-- rather than a door with a lock on it.
revoke all on schema clinic from public;
revoke all on schema clinic from anon;
grant usage on schema clinic to authenticated;

-- ---------------------------------------------------------------- enums ----

-- The clinic's roles are the CLINIC's business and live here, deliberately not
-- as new values on public.user_role. Two reasons:
--
--   1. `alter type ... add value` cannot USE the new value in the same
--      transaction that added it unless the type was created there too. This
--      file is pasted into the SQL editor as part of one big script, and a
--      policy referencing 'doctor' would fail on an already-installed database
--      — the exact "works on a fresh install, breaks on an upgrade" trap
--      20260810100000_schema.sql:12 warns about.
--   2. A doctor has no role in the shop. Extending the shop's enum would imply
--      otherwise and invite somebody to check `is_manager()` for a doctor.
do $$ begin create type clinic.staff_role as enum ('doctor','reception','director');
exception when duplicate_object then null; end $$;

-- A visit's journey through the day. `booked` exists before the patient
-- arrives; everything else is physical.
do $$ begin create type clinic.visit_status as enum
  ('booked','waiting','in_room','done','no_show','cancelled');
exception when duplicate_object then null; end $$;

do $$ begin create type clinic.visit_kind as enum ('new','follow_up');
exception when duplicate_object then null; end $$;

-- A clinical record is not a row. `issued` is the point of no return: after
-- it, a correction is a NEW record that points back at this one. Shared by
-- encounters and prescriptions because it is the same rule about the same kind
-- of document. See clinic.freeze_issued_rx() in 20260812100002_clinic_rx.sql.
do $$ begin create type clinic.record_status as enum ('draft','issued','cancelled');
exception when duplicate_object then null; end $$;

do $$ begin create type clinic.pay_method as enum ('cash','instapay','card','other');
exception when duplicate_object then null; end $$;

-- --------------------------------------------------------------- staff ----

-- One row per person who works here, hanging off the profile that already
-- carries their name, phone and password.
--
-- Their public.profiles.role stays 'customer' — meaning "no role in the SHOP".
-- A doctor is not a shop manager and must never see /admin. The clinic role is
-- the one below, and it is the only one any policy in this schema reads.
--
-- ⚠ THIS TABLE COMES BEFORE THE PREDICATES THAT READ IT, and the order is not
--   cosmetic: a `language sql` function is parsed when it is created, so
--   clinic.is_doctor() defined above this point fails with "relation
--   clinic.staff does not exist" on a fresh install.
create table if not exists clinic.staff (
  id            uuid primary key references public.profiles(id) on delete cascade,
  role          clinic.staff_role not null,

  -- How the name is PRINTED, which is not always how it is stored on the
  -- profile: "أحمد الفشاوي" in the staff list, "د. أحمد الفشاوي" on the
  -- prescription.
  display_name  text not null,
  title_ar      text,          -- استشاري / أخصائي
  specialty_ar  text,          -- باطنة وسكر
  syndicate_no  text,          -- رقم النقابة، بيتطبع على الروشتة

  -- The prescription number is built ON THE DEVICE so that a prescription can
  -- be written and printed with no network — see clinic.sync_prescription().
  -- This prefix is what keeps two doctors' offline counters from colliding.
  rx_prefix     text unique,

  signature_url text,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  -- Anyone who writes prescriptions needs a prefix, or their numbering
  -- collides with the next doctor's the first time the internet drops.
  constraint staff_clinician_needs_prefix
    check (role = 'reception' or rx_prefix is not null)
);

drop trigger if exists staff_touch on clinic.staff;
create trigger staff_touch before update on clinic.staff
  for each row execute function public.touch_updated_at();

-- ------------------------------------------------------------- helpers ----

-- Same shape and same reasoning as public.is_manager(): SECURITY DEFINER with
-- a pinned search_path, so a policy ON clinic.staff can ask "what is my role"
-- without recursing through that table's own policy, and so nobody who can
-- create a schema can shadow `staff` and answer the question themselves.

create or replace function clinic.my_role()
returns clinic.staff_role
language sql stable security definer set search_path = clinic, public as $$
  select role from clinic.staff where id = auth.uid() and is_active
$$;

create or replace function clinic.is_doctor()
returns boolean
language sql stable security definer set search_path = clinic, public as $$
  select exists (select 1 from clinic.staff
                  where id = auth.uid() and is_active and role = 'doctor')
$$;

create or replace function clinic.is_director()
returns boolean
language sql stable security definer set search_path = clinic, public as $$
  select exists (select 1 from clinic.staff
                  where id = auth.uid() and is_active and role = 'director')
$$;

create or replace function clinic.is_reception()
returns boolean
language sql stable security definer set search_path = clinic, public as $$
  select exists (select 1 from clinic.staff
                  where id = auth.uid() and is_active and role = 'reception')
$$;

-- Sees patients. The predicate that guards every clinical table — a director
-- examines patients too, so the two are one question, asked once.
create or replace function clinic.is_clinician()
returns boolean
language sql stable security definer set search_path = clinic, public as $$
  select exists (select 1 from clinic.staff
                  where id = auth.uid() and is_active
                    and role in ('doctor','director'))
$$;

-- Works here at all. Reception included — they book, weigh and take money.
create or replace function clinic.is_staff()
returns boolean
language sql stable security definer set search_path = clinic, public as $$
  select exists (select 1 from clinic.staff where id = auth.uid() and is_active)
$$;

-- ------------------------------------------------------------ settings ----

-- One row, same shape as public.site_settings. Unlike that table this one is
-- NOT readable by anon — nothing in this schema is.
create table if not exists clinic.settings (
  id boolean primary key default true check (id),

  clinic_name_ar text not null default 'العيادة',
  address_ar     text,
  phone          text,
  whatsapp_phone text,
  working_hours_ar text,

  -- ---- الطباعة ----
  -- The prescription prints on paper that ALREADY has the clinic's letterhead
  -- on it. These are the millimetres of that letterhead the print must not
  -- write over. They live in the database and not in the stylesheet because
  -- the day the print shop delivers a batch with a taller header, fixing it
  -- has to be a settings screen and not a deploy.
  header_offset_mm numeric(5,1) not null default 35.0
    check (header_offset_mm >= 0 and header_offset_mm <= 148),
  footer_offset_mm numeric(5,1) not null default 20.0
    check (footer_offset_mm >= 0 and footer_offset_mm <= 148),
  margin_x_mm      numeric(5,1) not null default 12.0
    check (margin_x_mm >= 0 and margin_x_mm <= 60),

  -- Plain paper instead of the pre-printed pad: draw the letterhead too. Also
  -- what the lab request sheet uses, which is never pre-printed.
  print_header boolean not null default false,

  -- ---- الفلوس ----
  consult_fee   numeric(10,2) not null default 0 check (consult_fee >= 0),
  follow_up_fee numeric(10,2) not null default 0 check (follow_up_fee >= 0),
  -- Within this many days of a visit, the return is a follow-up and not a new
  -- consultation. The number every receptionist argues about; stored once.
  follow_up_days int not null default 14 check (follow_up_days >= 0),
  currency      text not null default 'ج.م',

  -- Bumped whenever the drug catalogue changes. The device compares its cached
  -- version against this one and pulls only the delta — see
  -- clinic.drug_catalog() in 20260812100005_clinic_catalog.sql.
  drug_catalog_version bigint not null default 1,

  updated_at timestamptz not null default now()
);

drop trigger if exists clinic_settings_touch on clinic.settings;
create trigger clinic_settings_touch before update on clinic.settings
  for each row execute function public.touch_updated_at();

insert into clinic.settings (id) values (true) on conflict (id) do nothing;

-- ------------------------------------------------------------ patients ----

-- The file number a receptionist says out loud. A sequence, not a hash: "ملف
-- ١٤٧" is sayable and "ملف a3f9…" is not.
create sequence if not exists clinic.patient_file_seq start with 1000;

create table if not exists clinic.patients (
  id         uuid primary key default gen_random_uuid(),

  -- NULL until the row reaches the server. A patient registered while the
  -- internet was down has a real id (generated on the device) and no file
  -- number yet; clinic.sync_patient() assigns one on arrival. The alternative
  -- — letting the device invent a file number — produces two patients with
  -- file 148 the first time two devices are offline at once.
  file_no    bigint unique,

  full_name  text not null,
  -- Folded exactly the way web/lib/arabic.js folds the search box's input.
  -- tools/schema-check/verify.mjs asserts the two agree; without that, a
  -- patient filed from a keyboard typing "أحمد" cannot be found by someone
  -- typing "احمد".
  name_key   text generated always as (public.fold_arabic(full_name)) stored,

  phone      text,
  gender     text check (gender in ('male','female')),
  birth_date date,

  address_ar text,

  -- The two fields that change what a doctor is allowed to prescribe. They are
  -- plain text on purpose: a coded allergy list nobody maintains is worse than
  -- a sentence somebody actually wrote. The clinic screen prints this in red
  -- above the prescription builder.
  allergies_ar text,
  chronic_ar   text,

  notes_ar   text,

  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists patients_name_key_idx on clinic.patients (name_key text_pattern_ops);
create index if not exists patients_phone_idx    on clinic.patients (phone);
create index if not exists patients_created_idx  on clinic.patients (created_at desc);

drop trigger if exists patients_touch on clinic.patients;
create trigger patients_touch before update on clinic.patients
  for each row execute function public.touch_updated_at();

-- Phone stored the way public.normalize_phone() stores it everywhere else in
-- this database, so "٠١٠…" typed on an Arabic keyboard and "010…" typed on a
-- Latin one are the same patient.
create or replace function clinic.normalize_patient_phone()
returns trigger language plpgsql set search_path = clinic, public as $$
begin
  new.phone := nullif(public.normalize_phone(new.phone), '');
  return new;
end $$;

drop trigger if exists patients_phone_norm on clinic.patients;
create trigger patients_phone_norm before insert or update of phone on clinic.patients
  for each row execute function clinic.normalize_patient_phone();

-- -------------------------------------------------------------- visits ----

create table if not exists clinic.visits (
  id           uuid primary key default gen_random_uuid(),
  patient_id   uuid not null references clinic.patients(id) on delete cascade,
  doctor_id    uuid references clinic.staff(id) on delete set null,

  scheduled_at timestamptz,
  arrived_at   timestamptz,
  started_at   timestamptz,
  ended_at     timestamptz,

  status       clinic.visit_status not null default 'booked',
  kind         clinic.visit_kind   not null default 'new',

  -- Snapshotted from settings at booking time. Raising the fee next month must
  -- not rewrite what last month's patient was told — the same rule the shop
  -- applies to order lines (20260810100009_orders.sql:8).
  fee          numeric(10,2) not null default 0 check (fee >= 0),

  created_by   uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists visits_patient_idx  on clinic.visits (patient_id, created_at desc);
create index if not exists visits_doctor_idx   on clinic.visits (doctor_id, created_at desc);
create index if not exists visits_queue_idx    on clinic.visits (status, scheduled_at);

drop trigger if exists visits_touch on clinic.visits;
create trigger visits_touch before update on clinic.visits
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------- encounters ----

-- الكشف. The clinical record, and the table reception has no policy on at all.
--
-- Kept SEPARATE from visits rather than as more columns on it, and that split
-- is the whole privacy design: reception needs the appointment, the queue and
-- the money, and must not need a diagnosis to do any of it. Two tables let RLS
-- express that with a policy each. One table would leave it to the application
-- to remember, forever.
create table if not exists clinic.encounters (
  -- Generated on the device so the doctor can start writing with no network.
  id          uuid primary key,
  patient_id  uuid not null references clinic.patients(id) on delete cascade,
  -- Nullable: a walk-in the doctor sees without reception ever booking a visit
  -- is still a real encounter. P2's queue fills this in.
  visit_id    uuid references clinic.visits(id) on delete set null,

  -- WHO EXAMINED. Never taken from the client — every write path sets this
  -- from auth.uid(), and 20260812100001_clinic_rls.sql revokes UPDATE on the
  -- column so it cannot be moved afterwards.
  doctor_id   uuid not null references clinic.staff(id),

  -- العلامات الحيوية
  temp_c      numeric(4,1)  check (temp_c between 30 and 45),
  pulse       int           check (pulse between 20 and 300),
  bp_sys      int           check (bp_sys between 40 and 300),
  bp_dia      int           check (bp_dia between 20 and 200),
  weight_kg   numeric(5,1)  check (weight_kg between 0 and 400),
  height_cm   numeric(5,1)  check (height_cm between 0 and 260),

  complaint_ar text,
  history_ar   text,
  exam_ar      text,
  diagnosis_ar text,
  plan_ar      text,
  next_visit_on date,

  status      clinic.record_status not null default 'draft',
  signed_at   timestamptz,

  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists encounters_patient_idx on clinic.encounters (patient_id, created_at desc);
create index if not exists encounters_doctor_idx  on clinic.encounters (doctor_id, created_at desc);

drop trigger if exists encounters_touch on clinic.encounters;
create trigger encounters_touch before update on clinic.encounters
  for each row execute function public.touch_updated_at();

-- ------------------------------------------------------- prescriptions ----

create table if not exists clinic.prescriptions (
  -- The device generates this before the row has ever seen a server. It is
  -- also the idempotency key: clinic.sync_prescription() upserts on it, so a
  -- retry after a flaky reconnect produces one prescription and not two.
  id            uuid primary key,
  patient_id    uuid not null references clinic.patients(id) on delete cascade,
  encounter_id  uuid references clinic.encounters(id) on delete set null,
  doctor_id     uuid not null references clinic.staff(id),

  -- Built on the device: '{rx_prefix}-{yyyymmdd}-{counter}'. Unique across the
  -- clinic because the prefix is unique per doctor. Deliberately NOT a
  -- sequence — a sequence needs the server, and the whole point is that the
  -- prescription prints when the server is unreachable.
  rx_no         text not null unique,

  status        clinic.record_status not null default 'draft',
  issued_at     timestamptz,
  printed_count int not null default 0 check (printed_count >= 0),

  -- A correction is a NEW prescription pointing back at the one it replaces.
  -- The original stays in the file, because that is what a medical record is.
  amended_from  uuid references clinic.prescriptions(id) on delete set null,
  amend_reason  text,

  -- When it was written on the device, versus when the server first saw it.
  -- The gap is how long the clinic was offline, and it is worth being able to
  -- ask.
  written_at    timestamptz not null default now(),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists rx_patient_idx  on clinic.prescriptions (patient_id, written_at desc);
create index if not exists rx_doctor_idx    on clinic.prescriptions (doctor_id, written_at desc);
create index if not exists rx_amended_idx   on clinic.prescriptions (amended_from);

drop trigger if exists rx_touch on clinic.prescriptions;
create trigger rx_touch before update on clinic.prescriptions
  for each row execute function public.touch_updated_at();

-- The lines. SNAPSHOTS, not joins — renaming or delisting a drug next year is
-- forbidden from rewriting a prescription written this year. Same rule the
-- shop applies to order lines, and for the same reason: the paper in the
-- patient's hand and the row in the database have to say the same thing
-- forever.
create table if not exists clinic.prescription_items (
  rx_id       uuid not null references clinic.prescriptions(id) on delete cascade,
  line_no     int  not null check (line_no > 0),

  drug_id     uuid,          -- provenance only; may be null for a free-typed name
  drug_name   text not null, -- ← the snapshot, and what actually prints
  form_ar     text,          -- أقراص / شراب / أمبول
  strength    text,          -- 500 مجم

  dose_ar     text,          -- قرص
  frequency_ar text,         -- ٣ مرات يوميًا
  duration_ar  text,         -- ٧ أيام
  route_ar     text,         -- بالفم
  notes_ar     text,         -- بعد الأكل

  primary key (rx_id, line_no)
);

-- --------------------------------------------------------------- drugs ----

-- The catalogue. It is downloaded WHOLE onto every clinic device and searched
-- there, which is what makes "type one letter, see the drug" instant and what
-- makes it keep working with the internet off. Keep the row narrow: every
-- column here is multiplied by a few thousand and pushed over a phone
-- connection.
create table if not exists clinic.drugs (
  id         uuid primary key default gen_random_uuid(),
  trade_name text not null,

  -- The brand as an ARABIC-TYPING DOCTOR SPELLS IT. "كونكور" for Concor,
  -- "فلاجيل" for Flagyl.
  --
  -- Not decoration and not a translation: Egyptian doctors prescribe by brand,
  -- and half of them type Arabic. Without this column the search box answers
  -- "كونكور" with nothing at all while holding the drug, which is the single
  -- most likely way for this feature to feel broken on day one. Caught by an
  -- assertion in tools/schema-check/clinic.mjs, not by inspection.
  trade_name_ar text not null default '',

  generic_ar text,
  generic_en text,
  -- NOT NULL with an empty default, and that is load-bearing rather than
  -- fussy: NULLs are distinct from each other in a UNIQUE constraint, so
  -- (Panadol, null, null) could be inserted a hundred times and the constraint
  -- at the bottom of this table would never once complain.
  form_ar    text not null default '',
  strength   text not null default '',

  -- Folded by the same rule as web/lib/arabic.js, so the device's in-memory
  -- search and any server-side query give the same answer.
  name_key   text generated always as (
    public.fold_arabic(trade_name) || ' ' || public.fold_arabic(trade_name_ar)
    || ' ' || public.fold_arabic(coalesce(generic_ar,''))
    || ' ' || lower(coalesce(generic_en,''))
  ) stored,

  is_active  boolean not null default true,
  -- The delta cursor. clinic.drug_catalog(since) returns rows newer than this.
  updated_at timestamptz not null default now(),

  unique (trade_name, strength, form_ar)
);

create index if not exists drugs_name_key_idx on clinic.drugs (name_key text_pattern_ops);
create index if not exists drugs_updated_idx  on clinic.drugs (updated_at);

drop trigger if exists drugs_touch on clinic.drugs;
create trigger drugs_touch before update on clinic.drugs
  for each row execute function public.touch_updated_at();

-- How often THIS doctor reaches for THIS drug. Sorts their own habits to the
-- top of the picker, which is most of what makes the box feel fast after a
-- week of use.
create table if not exists clinic.drug_usage (
  doctor_id uuid not null references clinic.staff(id) on delete cascade,
  drug_id   uuid not null references clinic.drugs(id) on delete cascade,
  uses      int  not null default 0,
  last_used timestamptz not null default now(),
  primary key (doctor_id, drug_id)
);

-- ---------------------------------------------------------- بروتوكولات ----

-- The same four drugs for the same presentation, every day. One click instead
-- of four lines.
create table if not exists clinic.rx_templates (
  id         uuid primary key default gen_random_uuid(),
  -- NULL = shared with the whole clinic. Otherwise it is this doctor's own.
  doctor_id  uuid references clinic.staff(id) on delete cascade,
  name_ar    text not null,
  notes_ar   text,
  created_at timestamptz not null default now()
);

create table if not exists clinic.rx_template_items (
  template_id  uuid not null references clinic.rx_templates(id) on delete cascade,
  line_no      int  not null check (line_no > 0),
  drug_id      uuid references clinic.drugs(id) on delete set null,
  drug_name    text not null,
  form_ar      text,
  strength     text,
  dose_ar      text,
  frequency_ar text,
  duration_ar  text,
  route_ar     text,
  notes_ar     text,
  primary key (template_id, line_no)
);

-- ------------------------------------------------ تحاليل وأشعة (P4) ----

create table if not exists clinic.lab_tests (
  id        uuid primary key default gen_random_uuid(),
  name_ar   text not null,
  name_en   text,
  -- Same NOT NULL DEFAULT reasoning as clinic.drugs.form_ar: a nullable column
  -- inside a UNIQUE constraint does not deduplicate anything.
  category  text not null default 'تحاليل',   -- تحاليل / أشعة / وظائف
  name_key  text generated always as (public.fold_arabic(name_ar)) stored,
  is_active boolean not null default true,
  updated_at timestamptz not null default now(),
  unique (name_ar, category)
);

create table if not exists clinic.lab_requests (
  id           uuid primary key,
  patient_id   uuid not null references clinic.patients(id) on delete cascade,
  encounter_id uuid references clinic.encounters(id) on delete set null,
  doctor_id    uuid not null references clinic.staff(id),
  req_no       text not null unique,
  notes_ar     text,
  written_at   timestamptz not null default now(),
  created_at   timestamptz not null default now()
);

create table if not exists clinic.lab_request_items (
  req_id   uuid not null references clinic.lab_requests(id) on delete cascade,
  line_no  int  not null check (line_no > 0),
  test_id  uuid,
  test_name text not null,   -- snapshot, same rule as prescription_items
  notes_ar text,
  primary key (req_id, line_no)
);

-- Results the patient brings back, photographed. The bucket is private and
-- stays private — same shape as public.customer_uploads.
create table if not exists clinic.attachments (
  id           uuid primary key default gen_random_uuid(),
  patient_id   uuid not null references clinic.patients(id) on delete cascade,
  encounter_id uuid references clinic.encounters(id) on delete set null,
  storage_path text not null unique,
  original_name text,
  kind         text,     -- تحليل / أشعة / تقرير
  bytes        bigint,
  uploaded_by  uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now()
);

-- ------------------------------------------------------------ الفلوس ----

create table if not exists clinic.payments (
  id          uuid primary key default gen_random_uuid(),
  visit_id    uuid not null references clinic.visits(id) on delete cascade,
  amount      numeric(10,2) not null check (amount > 0),
  method      clinic.pay_method not null default 'cash',
  received_by uuid references public.profiles(id) on delete set null,
  note_ar     text,
  created_at  timestamptz not null default now()
);

create index if not exists payments_visit_idx on clinic.payments (visit_id);
create index if not exists payments_day_idx   on clinic.payments (created_at);

-- ------------------------------------------------------------- الأثر ----

-- Who did what, and WHO LOOKED. A clinic where several doctors can open the
-- same file needs the second half of that sentence as much as the first — it
-- is the only thing that makes shared access reviewable rather than merely
-- convenient.
--
-- Append-only: 20260812100001_clinic_rls.sql grants INSERT and SELECT and
-- nothing else, to anyone, including the director.
create table if not exists clinic.audit_events (
  id         bigserial primary key,
  actor_id   uuid references public.profiles(id) on delete set null,
  action     text not null,        -- viewed_patient / issued_rx / amended_rx …
  entity     text not null,        -- patients / prescriptions …
  entity_id  uuid,
  detail     jsonb,
  created_at timestamptz not null default now()
);

create index if not exists audit_actor_idx  on clinic.audit_events (actor_id, created_at desc);
create index if not exists audit_entity_idx on clinic.audit_events (entity, entity_id);

-- ## 20260812100001_clinic_rls.sql
-- ============================================================================
--  العيادة — الصلاحيات
--
--  ⚠  Sorts AFTER 20260810100006_rls.sql, so nothing here is undone by it.
--
--  THE RULE FOR THIS WHOLE SCHEMA, AND IT HAS NO EXCEPTIONS:
--  `anon` gets nothing. Not a table, not a column, not a function. The shop has
--  a deliberate anonymous read surface because a shop window nobody can look
--  into is pointless; a patient file has no equivalent argument. anon does not
--  even hold USAGE on the schema (20260812100000_clinic_schema.sql:32), so
--  every grant below is a second lock on a door that has no handle.
--
--  Supabase sets `alter default privileges` for schema public only. A new
--  schema starts with no grants at all, which is exactly what we want: every
--  privilege below had to be typed out on purpose.
--
--  WHO SEES WHAT
--
--    reception  الاستقبال — patients, visits, queue, money. NEVER a diagnosis.
--    doctor     الدكتور    — everything clinical, for every patient in the
--                            clinic (one shared file), but WRITES only under
--                            their own name.
--    director   الديريكتور — a doctor, plus reports, staff and settings.
-- ============================================================================

alter table clinic.staff              enable row level security;
alter table clinic.settings           enable row level security;
alter table clinic.patients           enable row level security;
alter table clinic.visits             enable row level security;
alter table clinic.encounters         enable row level security;
alter table clinic.prescriptions      enable row level security;
alter table clinic.prescription_items enable row level security;
alter table clinic.drugs              enable row level security;
alter table clinic.drug_usage         enable row level security;
alter table clinic.rx_templates       enable row level security;
alter table clinic.rx_template_items  enable row level security;
alter table clinic.lab_tests          enable row level security;
alter table clinic.lab_requests       enable row level security;
alter table clinic.lab_request_items  enable row level security;
alter table clinic.attachments        enable row level security;
alter table clinic.payments           enable row level security;
alter table clinic.audit_events       enable row level security;

-- Belt and braces. anon has no USAGE on the schema, so it cannot reach these
-- names at all — but a future migration that grants USAGE by accident should
-- still find every table bare underneath.
revoke all on all tables    in schema clinic from anon, public;
revoke all on all functions in schema clinic from anon, public;
revoke all on all sequences in schema clinic from anon, public;

-- ---------------------------------------------------------------- staff ----

-- Every member of staff can read the staff list. Not a privacy hole — it is
-- how "كتبها: د. أحمد" appears under a prescription line, and how the queue
-- names the doctor a patient is waiting for.
drop policy if exists staff_read on clinic.staff;
create policy staff_read on clinic.staff
  for select to authenticated
  using (clinic.is_staff());

drop policy if exists staff_write on clinic.staff;
create policy staff_write on clinic.staff
  for all to authenticated
  using (clinic.is_director()) with check (clinic.is_director());

-- A doctor may fix how their own name and title PRINT without being able to
-- promote themselves. Same shape as the profiles.role lock in
-- 20260810100006_rls.sql:98: the privilege is taken at the column level, so
-- the rule cannot be argued around by a policy that reads "the row is mine".
revoke update on clinic.staff from authenticated;
grant  update (display_name, title_ar, specialty_ar, syndicate_no, signature_url)
  on clinic.staff to authenticated;

drop policy if exists staff_self_update on clinic.staff;
create policy staff_self_update on clinic.staff
  for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

grant select, insert, delete on clinic.staff to authenticated;

-- ------------------------------------------------------------- settings ----

drop policy if exists settings_read on clinic.settings;
create policy settings_read on clinic.settings
  for select to authenticated
  using (clinic.is_staff());

-- The print offsets are read by every prescription and changed by one person.
drop policy if exists settings_write on clinic.settings;
create policy settings_write on clinic.settings
  for all to authenticated
  using (clinic.is_director()) with check (clinic.is_director());

grant select, insert, update, delete on clinic.settings to authenticated;

-- ------------------------------------------------------------ patients ----

-- Reception registers patients and looks them up; that is the job. What they
-- cannot reach is clinic.encounters and clinic.prescriptions, below.
drop policy if exists patients_read on clinic.patients;
create policy patients_read on clinic.patients
  for select to authenticated
  using (clinic.is_staff());

drop policy if exists patients_write on clinic.patients;
create policy patients_write on clinic.patients
  for all to authenticated
  using (clinic.is_staff()) with check (clinic.is_staff());

-- The file number is assigned by clinic.sync_patient() and by nobody else. A
-- device that could set it would hand two patients the same number the first
-- time two devices registered someone while offline.
revoke update on clinic.patients from authenticated;
grant  update (full_name, phone, gender, birth_date, address_ar,
               allergies_ar, chronic_ar, notes_ar)
  on clinic.patients to authenticated;

grant select, insert, delete on clinic.patients to authenticated;

-- -------------------------------------------------------------- visits ----

drop policy if exists visits_read on clinic.visits;
create policy visits_read on clinic.visits
  for select to authenticated
  using (clinic.is_staff());

drop policy if exists visits_write on clinic.visits;
create policy visits_write on clinic.visits
  for all to authenticated
  using (clinic.is_staff()) with check (clinic.is_staff());

grant select, insert, update, delete on clinic.visits to authenticated;

-- ---------------------------------------------------------- encounters ----
--
--  READ is clinic-wide: any doctor opening a patient sees the whole file,
--  including what a colleague wrote. That is a deliberate CLINICAL decision,
--  not an oversight — a doctor who cannot see what the patient is already
--  taking is a doctor prescribing blind, and in a clinic where two doctors
--  share the same patients that is the likelier harm by far.
--
--  WRITE is yours alone. You author under your own name, you may correct your
--  own draft, and you may not touch a colleague's record. A disagreement is a
--  new encounter in your name, not an edit to theirs.

drop policy if exists encounters_read on clinic.encounters;
create policy encounters_read on clinic.encounters
  for select to authenticated
  using (clinic.is_clinician());

drop policy if exists encounters_insert on clinic.encounters;
create policy encounters_insert on clinic.encounters
  for insert to authenticated
  with check (clinic.is_clinician() and doctor_id = auth.uid());

drop policy if exists encounters_update on clinic.encounters;
create policy encounters_update on clinic.encounters
  for update to authenticated
  using (clinic.is_clinician() and doctor_id = auth.uid() and status = 'draft')
  with check (doctor_id = auth.uid());

-- No delete policy, on purpose. A clinical note is not deleted; a draft that
-- was never signed simply stays a draft.

-- Authorship and signature are set by the RPCs and are unreachable from the
-- client. Note the table-level revoke first: revoking a single column while a
-- table-level UPDATE grant stands would change nothing at all.
revoke update on clinic.encounters from authenticated;
grant  update (temp_c, pulse, bp_sys, bp_dia, weight_kg, height_cm,
               complaint_ar, history_ar, exam_ar, diagnosis_ar, plan_ar,
               next_visit_on, visit_id)
  on clinic.encounters to authenticated;

grant select, insert on clinic.encounters to authenticated;

-- ------------------------------------------------------- prescriptions ----

drop policy if exists rx_read on clinic.prescriptions;
create policy rx_read on clinic.prescriptions
  for select to authenticated
  using (clinic.is_clinician());

drop policy if exists rx_insert on clinic.prescriptions;
create policy rx_insert on clinic.prescriptions
  for insert to authenticated
  with check (clinic.is_clinician() and doctor_id = auth.uid());

drop policy if exists rx_update on clinic.prescriptions;
create policy rx_update on clinic.prescriptions
  for update to authenticated
  using (clinic.is_clinician() and doctor_id = auth.uid() and status = 'draft')
  with check (doctor_id = auth.uid());

-- status, rx_no, doctor_id and amended_from are all off the table. They move
-- only through clinic.issue_prescription() and clinic.amend_prescription(),
-- which are SECURITY DEFINER and therefore reach past this revoke. A rule you
-- can go around is a suggestion — the same sentence as
-- 20260810100009_orders.sql:298.
revoke update on clinic.prescriptions from authenticated;
grant  update (encounter_id) on clinic.prescriptions to authenticated;

grant select, insert on clinic.prescriptions to authenticated;

-- The lines follow their prescription: visible if it is, editable while it is
-- still your draft.
drop policy if exists rx_items_read on clinic.prescription_items;
create policy rx_items_read on clinic.prescription_items
  for select to authenticated
  using (clinic.is_clinician());

drop policy if exists rx_items_write on clinic.prescription_items;
create policy rx_items_write on clinic.prescription_items
  for all to authenticated
  using (exists (select 1 from clinic.prescriptions p
                  where p.id = rx_id and p.doctor_id = auth.uid()
                    and p.status = 'draft'))
  with check (exists (select 1 from clinic.prescriptions p
                       where p.id = rx_id and p.doctor_id = auth.uid()
                         and p.status = 'draft'));

grant select, insert, update, delete on clinic.prescription_items to authenticated;

-- --------------------------------------------------- كتالوج الأدوية ----

-- Read by every clinician, on every device, in full. Written by the director.
drop policy if exists drugs_read on clinic.drugs;
create policy drugs_read on clinic.drugs
  for select to authenticated
  using (clinic.is_staff());

drop policy if exists drugs_write on clinic.drugs;
create policy drugs_write on clinic.drugs
  for all to authenticated
  using (clinic.is_director()) with check (clinic.is_director());

grant select, insert, update, delete on clinic.drugs to authenticated;

drop policy if exists lab_tests_read on clinic.lab_tests;
create policy lab_tests_read on clinic.lab_tests
  for select to authenticated
  using (clinic.is_staff());

drop policy if exists lab_tests_write on clinic.lab_tests;
create policy lab_tests_write on clinic.lab_tests
  for all to authenticated
  using (clinic.is_director()) with check (clinic.is_director());

grant select, insert, update, delete on clinic.lab_tests to authenticated;

-- Your own habits, nobody else's. Reading another doctor's prescribing
-- frequency is not needed to sort your own picker.
drop policy if exists drug_usage_own on clinic.drug_usage;
create policy drug_usage_own on clinic.drug_usage
  for all to authenticated
  using (doctor_id = auth.uid()) with check (doctor_id = auth.uid());

grant select, insert, update, delete on clinic.drug_usage to authenticated;

-- ------------------------------------------------------- بروتوكولات ----

-- Yours, or the clinic's shared ones (doctor_id is null).
drop policy if exists rx_templates_read on clinic.rx_templates;
create policy rx_templates_read on clinic.rx_templates
  for select to authenticated
  using (clinic.is_clinician() and (doctor_id is null or doctor_id = auth.uid()));

drop policy if exists rx_templates_write on clinic.rx_templates;
create policy rx_templates_write on clinic.rx_templates
  for all to authenticated
  using (doctor_id = auth.uid() or (doctor_id is null and clinic.is_director()))
  with check (doctor_id = auth.uid() or (doctor_id is null and clinic.is_director()));

grant select, insert, update, delete on clinic.rx_templates to authenticated;

drop policy if exists rx_template_items_all on clinic.rx_template_items;
create policy rx_template_items_all on clinic.rx_template_items
  for all to authenticated
  using (exists (select 1 from clinic.rx_templates t
                  where t.id = template_id
                    and (t.doctor_id = auth.uid()
                         or (t.doctor_id is null and clinic.is_clinician()))))
  with check (exists (select 1 from clinic.rx_templates t
                       where t.id = template_id
                         and (t.doctor_id = auth.uid()
                              or (t.doctor_id is null and clinic.is_director()))));

grant select, insert, update, delete on clinic.rx_template_items to authenticated;

-- --------------------------------------------------- تحاليل ومرفقات ----

drop policy if exists lab_req_read on clinic.lab_requests;
create policy lab_req_read on clinic.lab_requests
  for select to authenticated
  using (clinic.is_clinician());

drop policy if exists lab_req_write on clinic.lab_requests;
create policy lab_req_write on clinic.lab_requests
  for all to authenticated
  using (clinic.is_clinician() and doctor_id = auth.uid())
  with check (clinic.is_clinician() and doctor_id = auth.uid());

grant select, insert, update, delete on clinic.lab_requests to authenticated;

drop policy if exists lab_req_items_all on clinic.lab_request_items;
create policy lab_req_items_all on clinic.lab_request_items
  for all to authenticated
  using (clinic.is_clinician())
  with check (exists (select 1 from clinic.lab_requests r
                       where r.id = req_id and r.doctor_id = auth.uid()));

grant select, insert, update, delete on clinic.lab_request_items to authenticated;

-- A scanned result is a clinical document. Reception hands the paper over; it
-- does not read it.
drop policy if exists attachments_read on clinic.attachments;
create policy attachments_read on clinic.attachments
  for select to authenticated
  using (clinic.is_clinician());

drop policy if exists attachments_write on clinic.attachments;
create policy attachments_write on clinic.attachments
  for all to authenticated
  using (clinic.is_clinician()) with check (clinic.is_clinician());

grant select, insert, update, delete on clinic.attachments to authenticated;

-- ------------------------------------------------------------- الفلوس ----
--
--  Reception takes the money and must see the day's takings to balance the
--  drawer. A doctor sees what was collected against their OWN visits — enough
--  to check their day, not enough to audit a colleague's. The director sees
--  everything, which is the whole point of the role.

drop policy if exists payments_read on clinic.payments;
create policy payments_read on clinic.payments
  for select to authenticated
  using (
    clinic.is_reception()
    or clinic.is_director()
    or exists (select 1 from clinic.visits v
                where v.id = visit_id and v.doctor_id = auth.uid())
  );

drop policy if exists payments_write on clinic.payments;
create policy payments_write on clinic.payments
  for all to authenticated
  using (clinic.is_reception() or clinic.is_director())
  with check (clinic.is_reception() or clinic.is_director());

grant select, insert, update, delete on clinic.payments to authenticated;

-- -------------------------------------------------------------- الأثر ----
--
--  APPEND-ONLY, for everyone. There is no UPDATE policy and no DELETE policy
--  on this table and there must never be one — including for the director. An
--  audit log the audited party can edit is decoration.

drop policy if exists audit_insert on clinic.audit_events;
create policy audit_insert on clinic.audit_events
  for insert to authenticated
  with check (clinic.is_staff() and actor_id = auth.uid());

drop policy if exists audit_read on clinic.audit_events;
create policy audit_read on clinic.audit_events
  for select to authenticated
  using (clinic.is_director());

grant select, insert on clinic.audit_events to authenticated;
grant usage on sequence clinic.audit_events_id_seq to authenticated;

-- ---------------------------------------------------------------------------
--  The predicates themselves. Executable by a signed-in session, because every
--  policy above calls them; never by anon.
-- ---------------------------------------------------------------------------
revoke execute on function clinic.my_role()      from public, anon;
revoke execute on function clinic.is_doctor()    from public, anon;
revoke execute on function clinic.is_director()  from public, anon;
revoke execute on function clinic.is_reception() from public, anon;
revoke execute on function clinic.is_clinician() from public, anon;
revoke execute on function clinic.is_staff()     from public, anon;

grant execute on function clinic.my_role()      to authenticated;
grant execute on function clinic.is_doctor()    to authenticated;
grant execute on function clinic.is_director()  to authenticated;
grant execute on function clinic.is_reception() to authenticated;
grant execute on function clinic.is_clinician() to authenticated;
grant execute on function clinic.is_staff()     to authenticated;

-- ## 20260812100002_clinic_rx.sql
-- ============================================================================
--  العيادة — الروشتة
--
--  ⚠  Sorts AFTER 20260810100006_rls.sql. Carries its own grants, at the
--     bottom.
--
--  Two problems are solved here and they pull in opposite directions.
--
--  1. A PRESCRIPTION MUST BE WRITABLE AND PRINTABLE WITH NO NETWORK. The
--     clinic's internet drops mid-session and the patient is standing there.
--     So the device generates the id, generates the number, writes to its own
--     IndexedDB, and prints from there. The server sees it later.
--
--  2. A PRESCRIPTION IS A MEDICAL RECORD. Once issued it does not change. A
--     correction is a NEW prescription that points back at the old one, and
--     both stay in the file.
--
--  The reconciliation is clinic.sync_prescription(): IDEMPOTENT on the id the
--  device generated. A reconnect that retries a request whose response was
--  lost produces one prescription, not two. That single property is what makes
--  offline writing safe here, and it is why prescriptions are append-only and
--  authored by exactly one device — the moment two devices could edit one row,
--  none of this would hold.
-- ============================================================================

-- ---------------------------------------------------------------------------
--  القفل — الروشتة اللي اتطبعت مش بتتعدّل
--
--  20260812100001_clinic_rls.sql already revoked UPDATE on every column that
--  matters, so a client cannot reach these. This trigger is the second lock:
--  it also binds the SECURITY DEFINER functions below, which run as the owner
--  and sail straight past a grant.
-- ---------------------------------------------------------------------------
create or replace function clinic.freeze_issued_rx()
returns trigger
language plpgsql set search_path = clinic, public as $$
begin
  if old.status = 'issued' then
    -- Cancelling an issued prescription is legitimate — the patient never
    -- collected it, the drug was out of stock. Everything else is not.
    if new.status is distinct from old.status and new.status <> 'cancelled' then
      raise exception 'RX_ISSUED' using errcode = 'P0001';
    end if;

    if new.rx_no      is distinct from old.rx_no
    or new.patient_id is distinct from old.patient_id
    or new.doctor_id  is distinct from old.doctor_id
    or new.encounter_id is distinct from old.encounter_id
    or new.written_at is distinct from old.written_at
    or new.issued_at  is distinct from old.issued_at
    or new.amended_from is distinct from old.amended_from
    then
      raise exception 'RX_ISSUED' using errcode = 'P0001';
    end if;
    -- printed_count and updated_at are free to move. Printing a second copy
    -- is not an amendment.
  end if;
  return new;
end $$;

drop trigger if exists rx_freeze on clinic.prescriptions;
create trigger rx_freeze before update on clinic.prescriptions
  for each row execute function clinic.freeze_issued_rx();

-- The lines are frozen with the prescription. The RLS policy on
-- prescription_items already requires the parent to be a draft; this catches
-- the definer path too.
--
-- NOTE the TG_OP branch. In a DELETE trigger PL/pgSQL leaves NEW unassigned,
-- and `coalesce(new.rx_id, old.rx_id)` does not evaluate to OLD — it raises
-- "record new is not assigned yet" and takes the delete down with it.
create or replace function clinic.freeze_issued_rx_items()
returns trigger
language plpgsql set search_path = clinic, public as $$
declare
  v_rx     uuid;
  v_status clinic.record_status;
begin
  v_rx := case when tg_op = 'DELETE' then old.rx_id else new.rx_id end;

  select status into v_status from clinic.prescriptions where id = v_rx;
  if v_status = 'issued' then
    raise exception 'RX_ISSUED' using errcode = 'P0001';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end $$;

drop trigger if exists rx_items_freeze on clinic.prescription_items;
create trigger rx_items_freeze before insert or update or delete
  on clinic.prescription_items
  for each row execute function clinic.freeze_issued_rx_items();

-- ---------------------------------------------------------------------------
--  الكشف — رفع من الجهاز
--
--  Same shape as the prescription: the device owns the id, the server decides
--  authorship. An encounter is editable while it is a draft and frozen once
--  signed, which is what `signed` means.
-- ---------------------------------------------------------------------------
create or replace function clinic.sync_encounter(p_payload jsonb)
returns uuid
language plpgsql security definer set search_path = clinic, public as $$
declare
  v_id      uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_patient uuid := nullif(p_payload ->> 'patient_id', '')::uuid;
  v_owner   uuid;
  v_status  clinic.record_status;
begin
  if not clinic.is_clinician() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if v_id is null or v_patient is null then
    raise exception 'BAD_PAYLOAD' using errcode = 'P0001';
  end if;
  if not exists (select 1 from clinic.patients where id = v_patient) then
    raise exception 'NO_PATIENT' using errcode = 'P0001';
  end if;

  select doctor_id, status into v_owner, v_status
    from clinic.encounters where id = v_id;

  if v_owner is not null then
    if v_owner <> auth.uid() then
      raise exception 'NOT_YOURS' using errcode = 'P0001';
    end if;
    -- The retry case. A signed encounter that arrives again is the same
    -- encounter; say yes and change nothing.
    if v_status = 'issued' then
      return v_id;
    end if;
  end if;

  insert into clinic.encounters as e (
    id, patient_id, visit_id, doctor_id,
    temp_c, pulse, bp_sys, bp_dia, weight_kg, height_cm,
    complaint_ar, history_ar, exam_ar, diagnosis_ar, plan_ar, next_visit_on,
    status, signed_at
  ) values (
    v_id, v_patient,
    nullif(p_payload ->> 'visit_id', '')::uuid,
    auth.uid(),                                  -- ← never from the payload
    nullif(p_payload ->> 'temp_c','')::numeric,
    nullif(p_payload ->> 'pulse','')::int,
    nullif(p_payload ->> 'bp_sys','')::int,
    nullif(p_payload ->> 'bp_dia','')::int,
    nullif(p_payload ->> 'weight_kg','')::numeric,
    nullif(p_payload ->> 'height_cm','')::numeric,
    nullif(p_payload ->> 'complaint_ar',''),
    nullif(p_payload ->> 'history_ar',''),
    nullif(p_payload ->> 'exam_ar',''),
    nullif(p_payload ->> 'diagnosis_ar',''),
    nullif(p_payload ->> 'plan_ar',''),
    nullif(p_payload ->> 'next_visit_on','')::date,
    coalesce(nullif(p_payload ->> 'status','')::clinic.record_status, 'draft'),
    case when p_payload ->> 'status' = 'issued' then now() end
  )
  on conflict (id) do update set
    visit_id      = excluded.visit_id,
    temp_c        = excluded.temp_c,
    pulse         = excluded.pulse,
    bp_sys        = excluded.bp_sys,
    bp_dia        = excluded.bp_dia,
    weight_kg     = excluded.weight_kg,
    height_cm     = excluded.height_cm,
    complaint_ar  = excluded.complaint_ar,
    history_ar    = excluded.history_ar,
    exam_ar       = excluded.exam_ar,
    diagnosis_ar  = excluded.diagnosis_ar,
    plan_ar       = excluded.plan_ar,
    next_visit_on = excluded.next_visit_on,
    status        = excluded.status,
    signed_at     = coalesce(e.signed_at, excluded.signed_at);

  return v_id;
end $$;

-- ---------------------------------------------------------------------------
--  الروشتة — رفع من الجهاز، والرفع مرتين = روشتة واحدة
-- ---------------------------------------------------------------------------
create or replace function clinic.sync_prescription(p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = clinic, public as $$
declare
  v_id       uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_patient  uuid := nullif(p_payload ->> 'patient_id', '')::uuid;
  v_rx_no    text := nullif(trim(p_payload ->> 'rx_no'), '');
  v_status   clinic.record_status :=
               coalesce(nullif(p_payload ->> 'status','')::clinic.record_status, 'draft');
  v_prefix   text;
  v_owner    uuid;
  v_existing clinic.record_status;
  v_item     jsonb;
  v_lines    int := 0;
begin
  if not clinic.is_clinician() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if v_id is null or v_patient is null or v_rx_no is null then
    raise exception 'BAD_PAYLOAD' using errcode = 'P0001';
  end if;
  if not exists (select 1 from clinic.patients where id = v_patient) then
    raise exception 'NO_PATIENT' using errcode = 'P0001';
  end if;

  -- The number was built on the device from this doctor's own prefix. Checking
  -- it here is what stops one doctor's device — through a bug or otherwise —
  -- from filing prescriptions inside a colleague's numbering, which would make
  -- the director's report quietly wrong rather than loudly broken.
  select rx_prefix into v_prefix from clinic.staff where id = auth.uid();
  if v_prefix is null or v_rx_no not like v_prefix || '-%' then
    raise exception 'RX_PREFIX_MISMATCH' using errcode = 'P0001';
  end if;

  select doctor_id, status into v_owner, v_existing
    from clinic.prescriptions where id = v_id;

  if v_owner is not null then
    if v_owner <> auth.uid() then
      raise exception 'NOT_YOUR_RX' using errcode = 'P0001';
    end if;
    -- ⚠ THE IDEMPOTENCY CASE, and the reason this function exists.
    -- The device sent this, the reply was lost to a dying connection, and the
    -- outbox is retrying. The prescription is already here and already issued;
    -- return it and touch nothing. Inserting again would put a second copy of
    -- the same paper in the patient's file.
    if v_existing = 'issued' then
      return jsonb_build_object('id', v_id, 'rx_no', v_rx_no,
                                'status', 'issued', 'duplicate', true);
    end if;
  end if;

  insert into clinic.prescriptions as r (
    id, patient_id, encounter_id, doctor_id, rx_no, status, issued_at, written_at
  ) values (
    v_id, v_patient,
    nullif(p_payload ->> 'encounter_id', '')::uuid,
    auth.uid(),                                  -- ← never from the payload
    v_rx_no, 'draft', null,
    coalesce(nullif(p_payload ->> 'written_at','')::timestamptz, now())
  )
  on conflict (id) do update set
    encounter_id = excluded.encounter_id,
    patient_id   = excluded.patient_id;

  -- Lines are replaced wholesale while the prescription is a draft. Merging
  -- them would need a stable line identity the device has no reason to keep.
  delete from clinic.prescription_items where rx_id = v_id;

  for v_item in select * from jsonb_array_elements(coalesce(p_payload -> 'items', '[]'::jsonb))
  loop
    if nullif(trim(v_item ->> 'drug_name'), '') is null then
      raise exception 'RX_LINE_EMPTY' using errcode = 'P0001';
    end if;
    v_lines := v_lines + 1;

    insert into clinic.prescription_items (
      rx_id, line_no, drug_id, drug_name, form_ar, strength,
      dose_ar, frequency_ar, duration_ar, route_ar, notes_ar
    ) values (
      v_id, v_lines,
      nullif(v_item ->> 'drug_id','')::uuid,
      trim(v_item ->> 'drug_name'),
      nullif(v_item ->> 'form_ar',''),
      nullif(v_item ->> 'strength',''),
      nullif(v_item ->> 'dose_ar',''),
      nullif(v_item ->> 'frequency_ar',''),
      nullif(v_item ->> 'duration_ar',''),
      nullif(v_item ->> 'route_ar',''),
      nullif(v_item ->> 'notes_ar','')
    );

    -- This doctor's habits, for their own picker.
    if nullif(v_item ->> 'drug_id','') is not null then
      insert into clinic.drug_usage (doctor_id, drug_id, uses, last_used)
      values (auth.uid(), (v_item ->> 'drug_id')::uuid, 1, now())
      on conflict (doctor_id, drug_id) do update
        set uses = clinic.drug_usage.uses + 1, last_used = now();
    end if;
  end loop;

  if v_status = 'issued' then
    if v_lines = 0 then
      raise exception 'RX_EMPTY' using errcode = 'P0001';
    end if;
    update clinic.prescriptions
       set status = 'issued', issued_at = coalesce(issued_at, now())
     where id = v_id;

    insert into clinic.audit_events (actor_id, action, entity, entity_id, detail)
    values (auth.uid(), 'issued_rx', 'prescriptions', v_id,
            jsonb_build_object('rx_no', v_rx_no, 'lines', v_lines,
                               'offline_for_seconds',
                               extract(epoch from now() -
                                 coalesce(nullif(p_payload ->> 'written_at','')::timestamptz, now()))::bigint));
  end if;

  return jsonb_build_object('id', v_id, 'rx_no', v_rx_no,
                            'status', v_status, 'duplicate', false);
end $$;

-- ---------------------------------------------------------------------------
--  إصدار روشتة كانت مسوّدة
-- ---------------------------------------------------------------------------
create or replace function clinic.issue_prescription(p_id uuid)
returns void
language plpgsql security definer set search_path = clinic, public as $$
declare v_owner uuid; v_status clinic.record_status; v_lines int;
begin
  select doctor_id, status into v_owner, v_status
    from clinic.prescriptions where id = p_id;

  if v_owner is null then
    raise exception 'NO_RX' using errcode = 'P0001';
  end if;
  if v_owner <> auth.uid() then
    raise exception 'NOT_YOUR_RX' using errcode = 'P0001';
  end if;
  if v_status = 'issued' then
    return;                    -- already done; saying so twice is not an error
  end if;

  select count(*) into v_lines from clinic.prescription_items where rx_id = p_id;
  if v_lines = 0 then
    raise exception 'RX_EMPTY' using errcode = 'P0001';
  end if;

  update clinic.prescriptions
     set status = 'issued', issued_at = now()
   where id = p_id;

  insert into clinic.audit_events (actor_id, action, entity, entity_id)
  values (auth.uid(), 'issued_rx', 'prescriptions', p_id);
end $$;

-- ---------------------------------------------------------------------------
--  التعديل — نسخة جديدة، والأصل مايتلمسش
--
--  Any clinician may amend, including a colleague, and this is NOT a hole in
--  the "you cannot edit another doctor's record" rule: the colleague's row is
--  not touched at all. What happens is a new prescription, in the amender's
--  own name, carrying a pointer back. Both papers stay in the file and the
--  audit log says who wrote which — which is exactly what a second doctor
--  correcting a dose should leave behind.
-- ---------------------------------------------------------------------------
create or replace function clinic.amend_prescription(p_id uuid, p_reason text)
returns uuid
language plpgsql security definer set search_path = clinic, public as $$
declare
  v_new    uuid := gen_random_uuid();
  v_prefix text;
  v_seq    bigint;
  v_src    clinic.prescriptions%rowtype;
begin
  if not clinic.is_clinician() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if nullif(trim(coalesce(p_reason,'')), '') is null then
    raise exception 'AMEND_REASON_REQUIRED' using errcode = 'P0001';
  end if;

  select * into v_src from clinic.prescriptions where id = p_id;
  if v_src.id is null then
    raise exception 'NO_RX' using errcode = 'P0001';
  end if;

  select rx_prefix into v_prefix from clinic.staff where id = auth.uid();

  -- This one IS numbered on the server: amending needs the original in front
  -- of you, so it never happens offline, and a server-side counter avoids
  -- colliding with whatever the device's local counter is up to.
  select count(*) + 1 into v_seq
    from clinic.prescriptions
   where doctor_id = auth.uid()
     and written_at::date = current_date;

  insert into clinic.prescriptions (
    id, patient_id, encounter_id, doctor_id, rx_no, status,
    amended_from, amend_reason, written_at
  ) values (
    v_new, v_src.patient_id, v_src.encounter_id, auth.uid(),
    v_prefix || '-' || to_char(current_date, 'YYYYMMDD') || '-ت' || lpad(v_seq::text, 4, '0'),
    'draft', p_id, trim(p_reason), now()
  );

  insert into clinic.prescription_items (
    rx_id, line_no, drug_id, drug_name, form_ar, strength,
    dose_ar, frequency_ar, duration_ar, route_ar, notes_ar
  )
  select v_new, line_no, drug_id, drug_name, form_ar, strength,
         dose_ar, frequency_ar, duration_ar, route_ar, notes_ar
    from clinic.prescription_items where rx_id = p_id;

  insert into clinic.audit_events (actor_id, action, entity, entity_id, detail)
  values (auth.uid(), 'amended_rx', 'prescriptions', v_new,
          jsonb_build_object('amended_from', p_id, 'reason', trim(p_reason)));

  return v_new;
end $$;

-- ---------------------------------------------------------------------------
--  طبعتها — عدّاد، مش تعديل
-- ---------------------------------------------------------------------------
create or replace function clinic.mark_printed(p_id uuid)
returns void
language plpgsql security definer set search_path = clinic, public as $$
begin
  if not clinic.is_clinician() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  update clinic.prescriptions set printed_count = printed_count + 1 where id = p_id;
end $$;

-- ---------------------------------------------------------------------------
--  ملف المريض كامل — زيارات وكشوفات وروشتات، وقدام كل واحدة اسم دكتورها
--
--  ONE call rather than five round trips, because this is what opens when a
--  patient sits down and the clinic's connection is the slow part.
-- ---------------------------------------------------------------------------
create or replace function clinic.patient_file(p_patient uuid)
returns jsonb
language sql stable security definer set search_path = clinic, public as $$
  select case when not clinic.is_clinician() then null else jsonb_build_object(
    'patient', (select to_jsonb(p) from clinic.patients p where p.id = p_patient),
    'encounters', coalesce((
      select jsonb_agg(x order by x ->> 'created_at' desc) from (
        select to_jsonb(e) || jsonb_build_object('doctor_name', s.display_name) as x
          from clinic.encounters e
          join clinic.staff s on s.id = e.doctor_id
         where e.patient_id = p_patient
      ) t), '[]'::jsonb),
    'prescriptions', coalesce((
      select jsonb_agg(x order by x ->> 'written_at' desc) from (
        select to_jsonb(r)
             || jsonb_build_object(
                  'doctor_name', s.display_name,
                  'superseded', exists (select 1 from clinic.prescriptions c
                                         where c.amended_from = r.id),
                  'items', coalesce((
                    select jsonb_agg(to_jsonb(i) order by i.line_no)
                      from clinic.prescription_items i where i.rx_id = r.id), '[]'::jsonb)
                ) as x
          from clinic.prescriptions r
          join clinic.staff s on s.id = r.doctor_id
         where r.patient_id = p_patient
      ) t), '[]'::jsonb)
  ) end
$$;

-- ---------------------------------------------------------------- grants ---

revoke execute on function clinic.sync_encounter(jsonb)          from public, anon;
revoke execute on function clinic.sync_prescription(jsonb)       from public, anon;
revoke execute on function clinic.issue_prescription(uuid)       from public, anon;
revoke execute on function clinic.amend_prescription(uuid, text) from public, anon;
revoke execute on function clinic.mark_printed(uuid)             from public, anon;
revoke execute on function clinic.patient_file(uuid)             from public, anon;
revoke execute on function clinic.freeze_issued_rx()             from public, anon;
revoke execute on function clinic.freeze_issued_rx_items()       from public, anon;

grant execute on function clinic.sync_encounter(jsonb)          to authenticated;
grant execute on function clinic.sync_prescription(jsonb)       to authenticated;
grant execute on function clinic.issue_prescription(uuid)       to authenticated;
grant execute on function clinic.amend_prescription(uuid, text) to authenticated;
grant execute on function clinic.mark_printed(uuid)             to authenticated;
grant execute on function clinic.patient_file(uuid)             to authenticated;

-- ## 20260812100003_clinic_visits.sql
-- ============================================================================
--  العيادة — المرضى والزيارات والطابور
--
--  ⚠  Sorts AFTER 20260810100006_rls.sql. Carries its own grants, at the
--     bottom.
-- ============================================================================

-- ---------------------------------------------------------------------------
--  تسجيل مريض — من الجهاز، وممكن يكون اتسجّل والنت مقطوع
--
--  The device owns the id. The SERVER owns the file number, and that split is
--  deliberate: two receptionists registering someone while the internet is
--  down would both hand out file 148 if the device could choose. So a patient
--  arrives here with a real id and a null file_no, and leaves with a number.
-- ---------------------------------------------------------------------------
create or replace function clinic.sync_patient(p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = clinic, public as $$
declare
  v_id   uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_name text := nullif(trim(p_payload ->> 'full_name'), '');
  v_file bigint;
begin
  if not clinic.is_staff() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if v_id is null then
    raise exception 'BAD_PAYLOAD' using errcode = 'P0001';
  end if;
  if v_name is null then
    raise exception 'NAME_REQUIRED' using errcode = 'P0001';
  end if;

  select file_no into v_file from clinic.patients where id = v_id;

  insert into clinic.patients (
    id, file_no, full_name, phone, gender, birth_date,
    address_ar, allergies_ar, chronic_ar, notes_ar, created_by
  ) values (
    v_id,
    coalesce(v_file, nextval('clinic.patient_file_seq')),
    v_name,
    nullif(p_payload ->> 'phone',''),
    nullif(p_payload ->> 'gender',''),
    nullif(p_payload ->> 'birth_date','')::date,
    nullif(p_payload ->> 'address_ar',''),
    nullif(p_payload ->> 'allergies_ar',''),
    nullif(p_payload ->> 'chronic_ar',''),
    nullif(p_payload ->> 'notes_ar',''),
    auth.uid()
  )
  on conflict (id) do update set
    full_name    = excluded.full_name,
    phone        = excluded.phone,
    gender       = excluded.gender,
    birth_date   = excluded.birth_date,
    address_ar   = excluded.address_ar,
    allergies_ar = excluded.allergies_ar,
    chronic_ar   = excluded.chronic_ar,
    notes_ar     = excluded.notes_ar;

  select file_no into v_file from clinic.patients where id = v_id;
  return jsonb_build_object('id', v_id, 'file_no', v_file);
end $$;

-- ---------------------------------------------------------------------------
--  البحث — بالاسم العربي أو بالموبايل
--
--  Both sides of the comparison are folded by the same rule: `name_key` is a
--  generated column running public.fold_arabic(), and the term is folded here
--  by the same function. web/lib/arabic.js folds it a third time for the
--  device's offline search, and tools/schema-check/verify.mjs asserts all
--  three agree — without that, "أحمد" filed on one keyboard is unfindable from
--  another typing "احمد".
-- ---------------------------------------------------------------------------
create or replace function clinic.search_patients(p_term text, p_limit int default 30)
returns table (
  id uuid, file_no bigint, full_name text, phone text,
  gender text, birth_date date, allergies_ar text, chronic_ar text,
  last_visit timestamptz
)
language sql stable security definer set search_path = clinic, public as $$
  select p.id, p.file_no, p.full_name, p.phone,
         p.gender, p.birth_date, p.allergies_ar, p.chronic_ar,
         (select max(v.created_at) from clinic.visits v where v.patient_id = p.id)
    from clinic.patients p
   where clinic.is_staff()
     and (
       nullif(trim(coalesce(p_term,'')), '') is null
       or p.name_key like '%' || public.fold_arabic(trim(p_term)) || '%'
       or p.phone like public.normalize_phone(p_term) || '%'
       or p.file_no::text = regexp_replace(coalesce(p_term,''), '[^0-9]', '', 'g')
     )
   order by p.updated_at desc
   limit greatest(1, least(coalesce(p_limit, 30), 100))
$$;

-- ---------------------------------------------------------------------------
--  الزيارة والطابور
-- ---------------------------------------------------------------------------

-- Which fee applies. The receptionist argues about this every day; here it is
-- one rule, read from settings, snapshotted onto the visit at booking time so
-- that raising the price next month does not rewrite this month's paperwork.
create or replace function clinic.suggest_fee(p_patient uuid)
returns jsonb
language sql stable security definer set search_path = clinic, public as $$
  select case when not clinic.is_staff() then null else (
    select case
      when exists (
        select 1 from clinic.visits v
         where v.patient_id = p_patient
           and v.status = 'done'
           and v.created_at >= now() - (s.follow_up_days || ' days')::interval
      ) then jsonb_build_object('kind', 'follow_up', 'fee', s.follow_up_fee)
      else jsonb_build_object('kind', 'new', 'fee', s.consult_fee)
    end
    from clinic.settings s where s.id
  ) end
$$;

create or replace function clinic.book_visit(
  p_patient uuid,
  p_doctor  uuid,
  p_when    timestamptz default null
) returns uuid
language plpgsql security definer set search_path = clinic, public as $$
declare v_id uuid := gen_random_uuid(); v_sug jsonb;
begin
  if not clinic.is_staff() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if not exists (select 1 from clinic.patients where id = p_patient) then
    raise exception 'NO_PATIENT' using errcode = 'P0001';
  end if;
  if p_doctor is not null and not exists (
       select 1 from clinic.staff
        where id = p_doctor and is_active and role in ('doctor','director')) then
    raise exception 'NO_DOCTOR' using errcode = 'P0001';
  end if;

  v_sug := clinic.suggest_fee(p_patient);

  insert into clinic.visits (id, patient_id, doctor_id, scheduled_at, status, kind, fee, created_by)
  values (
    v_id, p_patient, p_doctor, coalesce(p_when, now()),
    case when p_when is null or p_when <= now() then 'waiting' else 'booked' end,
    (v_sug ->> 'kind')::clinic.visit_kind,
    (v_sug ->> 'fee')::numeric,
    auth.uid()
  );

  if p_when is null or p_when <= now() then
    update clinic.visits set arrived_at = now() where id = v_id;
  end if;

  return v_id;
end $$;

-- The status machine. In a FUNCTION and not an UPDATE policy, for the reason
-- 20260810100009_orders.sql:13 gives: a policy can say who may write, only a
-- function can say which move is legal.
create or replace function clinic.set_visit_status(p_id uuid, p_status clinic.visit_status)
returns void
language plpgsql security definer set search_path = clinic, public as $$
declare v_old clinic.visit_status;
begin
  if not clinic.is_staff() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;

  select status into v_old from clinic.visits where id = p_id;
  if v_old is null then
    raise exception 'NO_VISIT' using errcode = 'P0001';
  end if;
  if v_old in ('done','cancelled','no_show') then
    raise exception 'VISIT_FINAL' using errcode = 'P0001';
  end if;

  if not (
    (v_old = 'booked'  and p_status in ('waiting','cancelled','no_show')) or
    (v_old = 'waiting' and p_status in ('in_room','cancelled','no_show')) or
    (v_old = 'in_room' and p_status in ('done','waiting'))
  ) then
    raise exception 'VISIT_TRANSITION_NOT_ALLOWED' using errcode = 'P0001';
  end if;

  update clinic.visits
     set status     = p_status,
         arrived_at = case when p_status = 'waiting' then coalesce(arrived_at, now())
                           else arrived_at end,
         started_at = case when p_status = 'in_room' then coalesce(started_at, now())
                           else started_at end,
         ended_at   = case when p_status = 'done' then now() else ended_at end
   where id = p_id;
end $$;

-- طابور النهارده. Reception sees the whole board; a doctor sees the whole
-- board too — knowing three people are waiting for a colleague is how a clinic
-- decides who takes the next walk-in.
create or replace function clinic.today_queue()
returns table (
  visit_id uuid, patient_id uuid, file_no bigint, full_name text, phone text,
  doctor_id uuid, doctor_name text,
  status clinic.visit_status, kind clinic.visit_kind, fee numeric,
  scheduled_at timestamptz, arrived_at timestamptz,
  paid numeric
)
language sql stable security definer set search_path = clinic, public as $$
  select v.id, p.id, p.file_no, p.full_name, p.phone,
         v.doctor_id, s.display_name,
         v.status, v.kind, v.fee,
         v.scheduled_at, v.arrived_at,
         coalesce((select sum(y.amount) from clinic.payments y where y.visit_id = v.id), 0)
    from clinic.visits v
    join clinic.patients p on p.id = v.patient_id
    left join clinic.staff s on s.id = v.doctor_id
   where clinic.is_staff()
     and coalesce(v.scheduled_at, v.created_at)::date = current_date
   order by
     array_position(array['in_room','waiting','booked','done','no_show','cancelled']::text[],
                    v.status::text),
     coalesce(v.arrived_at, v.scheduled_at, v.created_at)
$$;

-- The numbers on the home screen. Same shape as public.admin_dashboard().
create or replace function clinic.clinic_home()
returns jsonb
language sql stable security definer set search_path = clinic, public as $$
  select case when not clinic.is_staff() then null else jsonb_build_object(
    'waiting',   (select count(*) from clinic.visits
                   where status = 'waiting'
                     and coalesce(scheduled_at, created_at)::date = current_date),
    'in_room',   (select count(*) from clinic.visits
                   where status = 'in_room'
                     and coalesce(scheduled_at, created_at)::date = current_date),
    'mine_today',(select count(*) from clinic.visits
                   where doctor_id = auth.uid()
                     and coalesce(scheduled_at, created_at)::date = current_date),
    'done_today',(select count(*) from clinic.visits
                   where status = 'done'
                     and coalesce(scheduled_at, created_at)::date = current_date),
    'patients',  (select count(*) from clinic.patients),
    -- Registered while offline and never reviewed for a duplicate. Reception
    -- clears this; a silent duplicate file is how a patient's history splits
    -- in two and never comes back together.
    'unreviewed',(select count(*) from clinic.patients p
                   where exists (select 1 from clinic.patients q
                                  where q.id <> p.id
                                    and q.name_key = p.name_key
                                    and coalesce(q.phone,'') = coalesce(p.phone,'')))
  ) end
$$;

-- ---------------------------------------------------------------- grants ---

revoke execute on function clinic.sync_patient(jsonb)                         from public, anon;
revoke execute on function clinic.search_patients(text, int)                  from public, anon;
revoke execute on function clinic.suggest_fee(uuid)                           from public, anon;
revoke execute on function clinic.book_visit(uuid, uuid, timestamptz)         from public, anon;
revoke execute on function clinic.set_visit_status(uuid, clinic.visit_status) from public, anon;
revoke execute on function clinic.today_queue()                               from public, anon;
revoke execute on function clinic.clinic_home()                               from public, anon;

grant execute on function clinic.sync_patient(jsonb)                         to authenticated;
grant execute on function clinic.search_patients(text, int)                  to authenticated;
grant execute on function clinic.suggest_fee(uuid)                           to authenticated;
grant execute on function clinic.book_visit(uuid, uuid, timestamptz)         to authenticated;
grant execute on function clinic.set_visit_status(uuid, clinic.visit_status) to authenticated;
grant execute on function clinic.today_queue()                               to authenticated;
grant execute on function clinic.clinic_home()                               to authenticated;

-- ## 20260812100004_clinic_billing.sql
-- ============================================================================
--  العيادة — الفلوس وتقارير الديريكتور
--
--  ⚠  Sorts AFTER 20260810100006_rls.sql. Carries its own grants, at the
--     bottom.
--
--  The director's question is one sentence — "مين كشف لمين، وإيه اللي اتكتب" —
--  and it is answered by two functions here. Both refuse anyone who is not the
--  director, INSIDE the function, rather than by hoping the panel hides a menu
--  item. RLS already stops a doctor reading a colleague's payments; these add
--  the aggregate view that RLS cannot express.
-- ============================================================================

create or replace function clinic.take_payment(
  p_visit  uuid,
  p_amount numeric,
  p_method clinic.pay_method default 'cash',
  p_note   text default null
) returns uuid
language plpgsql security definer set search_path = clinic, public as $$
declare v_id uuid := gen_random_uuid();
begin
  -- The doctor does not handle the money. Reception does, and the director
  -- covers reception on their day off.
  if not (clinic.is_reception() or clinic.is_director()) then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if coalesce(p_amount, 0) <= 0 then
    raise exception 'BAD_AMOUNT' using errcode = 'P0001';
  end if;
  if not exists (select 1 from clinic.visits where id = p_visit) then
    raise exception 'NO_VISIT' using errcode = 'P0001';
  end if;

  insert into clinic.payments (id, visit_id, amount, method, received_by, note_ar)
  values (v_id, p_visit, p_amount, coalesce(p_method, 'cash'), auth.uid(), nullif(trim(p_note),''));

  insert into clinic.audit_events (actor_id, action, entity, entity_id, detail)
  values (auth.uid(), 'took_payment', 'payments', v_id,
          jsonb_build_object('visit', p_visit, 'amount', p_amount));

  return v_id;
end $$;

-- ---------------------------------------------------------------------------
--  تقرير اليوم — الدرج في آخر اليوم
--
--  Reception balances the cash box against this. The doctor's own line is
--  visible to them; the whole sheet is reception's and the director's.
-- ---------------------------------------------------------------------------
create or replace function clinic.day_sheet(p_day date default current_date)
returns jsonb
language sql stable security definer set search_path = clinic, public as $$
  select case when not clinic.is_staff() then null else jsonb_build_object(
    'day', p_day,
    'visits',   (select count(*) from clinic.visits v
                  where coalesce(v.scheduled_at, v.created_at)::date = p_day
                    and v.status = 'done'),
    -- What the visits SHOULD have brought in…
    'due',      (select coalesce(sum(v.fee), 0) from clinic.visits v
                  where coalesce(v.scheduled_at, v.created_at)::date = p_day
                    and v.status = 'done'),
    -- …and what actually reached the drawer. The gap is the number worth
    -- looking at; showing only one of the two hides it.
    'collected',(select coalesce(sum(y.amount), 0) from clinic.payments y
                  where y.created_at::date = p_day),
    'by_method',(select coalesce(jsonb_object_agg(m, t), '{}'::jsonb) from (
                   select method::text as m, sum(amount) as t
                     from clinic.payments where created_at::date = p_day
                    group by method) q)
  ) end
$$;

-- ---------------------------------------------------------------------------
--  الديريكتور: كل دكتور كشف كام، وحصّل كام
-- ---------------------------------------------------------------------------
create or replace function clinic.report_by_doctor(
  p_from date default current_date,
  p_to   date default current_date
) returns table (
  doctor_id     uuid,
  doctor_name   text,
  visits        bigint,
  patients      bigint,
  encounters    bigint,
  prescriptions bigint,
  due           numeric,
  collected     numeric
)
language sql stable security definer set search_path = clinic, public as $$
  select s.id, s.display_name,
         (select count(*) from clinic.visits v
           where v.doctor_id = s.id and v.status = 'done'
             and coalesce(v.scheduled_at, v.created_at)::date between p_from and p_to),
         (select count(distinct v.patient_id) from clinic.visits v
           where v.doctor_id = s.id
             and coalesce(v.scheduled_at, v.created_at)::date between p_from and p_to),
         (select count(*) from clinic.encounters e
           where e.doctor_id = s.id and e.created_at::date between p_from and p_to),
         (select count(*) from clinic.prescriptions r
           where r.doctor_id = s.id and r.status = 'issued'
             and r.written_at::date between p_from and p_to),
         (select coalesce(sum(v.fee), 0) from clinic.visits v
           where v.doctor_id = s.id and v.status = 'done'
             and coalesce(v.scheduled_at, v.created_at)::date between p_from and p_to),
         (select coalesce(sum(y.amount), 0)
            from clinic.payments y join clinic.visits v on v.id = y.visit_id
           where v.doctor_id = s.id and y.created_at::date between p_from and p_to)
    from clinic.staff s
   where clinic.is_director()
     and s.role in ('doctor','director')
   order by s.display_name
$$;

-- ---------------------------------------------------------------------------
--  الديريكتور: مين كشف لمين، وإيه الروشتة اللي اتكتبت
--
--  The row-per-prescription view behind the report screen. Includes the lines,
--  because "الروشتات اللي انكتبت" without the drugs on them answers nothing.
-- ---------------------------------------------------------------------------
create or replace function clinic.report_prescriptions(
  p_from   date default current_date,
  p_to     date default current_date,
  p_doctor uuid default null
) returns table (
  rx_id       uuid,
  rx_no       text,
  written_at  timestamptz,
  status      clinic.record_status,
  doctor_id   uuid,
  doctor_name text,
  patient_id  uuid,
  file_no     bigint,
  patient_name text,
  diagnosis_ar text,
  amended_from uuid,
  items       jsonb
)
language sql stable security definer set search_path = clinic, public as $$
  select r.id, r.rx_no, r.written_at, r.status,
         r.doctor_id, s.display_name,
         p.id, p.file_no, p.full_name,
         e.diagnosis_ar,
         r.amended_from,
         coalesce((select jsonb_agg(to_jsonb(i) order by i.line_no)
                     from clinic.prescription_items i where i.rx_id = r.id), '[]'::jsonb)
    from clinic.prescriptions r
    join clinic.staff    s on s.id = r.doctor_id
    join clinic.patients p on p.id = r.patient_id
    left join clinic.encounters e on e.id = r.encounter_id
   where clinic.is_director()
     and r.written_at::date between p_from and p_to
     and (p_doctor is null or r.doctor_id = p_doctor)
   order by r.written_at desc
$$;

-- ---------------------------------------------------------------- grants ---

revoke execute on function clinic.take_payment(uuid, numeric, clinic.pay_method, text) from public, anon;
revoke execute on function clinic.day_sheet(date)                        from public, anon;
revoke execute on function clinic.report_by_doctor(date, date)           from public, anon;
revoke execute on function clinic.report_prescriptions(date, date, uuid) from public, anon;

grant execute on function clinic.take_payment(uuid, numeric, clinic.pay_method, text) to authenticated;
grant execute on function clinic.day_sheet(date)                        to authenticated;
grant execute on function clinic.report_by_doctor(date, date)           to authenticated;
grant execute on function clinic.report_prescriptions(date, date, uuid) to authenticated;

-- ## 20260812100005_clinic_catalog.sql
-- ============================================================================
--  العيادة — كتالوج الأدوية والتحاليل
--
--  ⚠  Sorts AFTER 20260810100006_rls.sql. Carries its own grants, at the
--     bottom.
--
--  THE CATALOGUE IS DOWNLOADED WHOLE ONTO EVERY CLINIC DEVICE.
--
--  That is the entire reason "type one letter, see the drug" is instant and
--  keeps working when the clinic's internet drops. A server-side search would
--  be both slower on every keystroke AND the first thing to fail at the moment
--  it is needed most.
--
--  So the sync has to be cheap to repeat: clinic.drug_catalog(since) returns
--  only rows touched after `since`, plus the catalogue version from settings.
--  First run pulls everything; every run after that pulls almost nothing.
-- ============================================================================

-- Any change to the catalogue bumps the version, so a device holding a stale
-- copy can tell without diffing a few thousand rows.
create or replace function clinic.bump_catalog_version()
returns trigger
language plpgsql set search_path = clinic, public as $$
begin
  update clinic.settings set drug_catalog_version = drug_catalog_version + 1 where id;
  return null;
end $$;

drop trigger if exists drugs_bump_version on clinic.drugs;
create trigger drugs_bump_version after insert or update or delete on clinic.drugs
  for each statement execute function clinic.bump_catalog_version();

-- ---------------------------------------------------------------------------
--  المزامنة — اللي اتغيّر بس
--
--  Deletions are handled by is_active rather than DELETE: a device that never
--  hears about a removed row would otherwise keep offering a drug the clinic
--  has withdrawn. A row flipped inactive still arrives in the delta and the
--  device drops it locally.
-- ---------------------------------------------------------------------------
create or replace function clinic.drug_catalog(p_since timestamptz default null)
returns jsonb
language sql stable security definer set search_path = clinic, public as $$
  select case when not clinic.is_staff() then null else jsonb_build_object(
    'version', (select drug_catalog_version from clinic.settings where id),
    'now',     now(),
    'drugs',   coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', d.id, 'trade_name', d.trade_name,
               'trade_name_ar', d.trade_name_ar,
               'generic_ar', d.generic_ar, 'generic_en', d.generic_en,
               'form_ar', d.form_ar, 'strength', d.strength,
               'name_key', d.name_key, 'is_active', d.is_active))
        from clinic.drugs d
       where p_since is null or d.updated_at > p_since), '[]'::jsonb),
    -- This doctor's own habits, so the picker can float what they actually
    -- prescribe to the top without a second round trip.
    'usage',   coalesce((
      select jsonb_object_agg(u.drug_id::text, u.uses)
        from clinic.drug_usage u where u.doctor_id = auth.uid()), '{}'::jsonb),
    'tests',   coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', t.id, 'name_ar', t.name_ar, 'name_en', t.name_en,
               'category', t.category, 'name_key', t.name_key,
               'is_active', t.is_active))
        from clinic.lab_tests t
       where p_since is null or t.updated_at > p_since), '[]'::jsonb)
  ) end
$$;

-- Adding a drug that is not in the list, from the prescription screen, without
-- leaving it. A catalogue nobody can extend at the moment of need is a
-- catalogue people work around by typing free text, and free text is what the
-- snapshot columns exist to avoid depending on.
create or replace function clinic.add_drug(
  p_trade_name    text,
  p_generic_ar    text default null,
  p_form_ar       text default '',
  p_strength      text default '',
  p_trade_name_ar text default ''
) returns uuid
language plpgsql security definer set search_path = clinic, public as $$
declare v_id uuid; v_name text := nullif(trim(coalesce(p_trade_name,'')), '');
begin
  if not clinic.is_clinician() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if v_name is null then
    raise exception 'NAME_REQUIRED' using errcode = 'P0001';
  end if;

  insert into clinic.drugs (trade_name, trade_name_ar, generic_ar, form_ar, strength)
  values (v_name, coalesce(trim(p_trade_name_ar), ''),
          nullif(trim(coalesce(p_generic_ar,'')),''),
          coalesce(trim(p_form_ar), ''), coalesce(trim(p_strength), ''))
  on conflict (trade_name, strength, form_ar) do update
    set is_active = true                    -- re-adding a withdrawn one revives it
  returning id into v_id;

  return v_id;
end $$;

-- ============================================================================
--  البذرة — أدوية شائعة في السوق المصري
--
--  A STARTING POINT, not a formulary. It exists so the picker is useful on day
--  one instead of empty, and every row is editable from the screen. The
--  clinic's own list — the drugs this doctor actually writes — is a better
--  seed than this one by a wide margin, and replacing it is a paste into the
--  drugs screen, not a migration.
--
--  Re-runnable: `on conflict do nothing`, keyed on (trade_name, strength,
--  form_ar).
-- ============================================================================
insert into clinic.drugs (trade_name, generic_ar, generic_en, form_ar, strength) values
  -- مسكنات وخافضات حرارة
  ('Panadol',      'باراسيتامول',            'Paracetamol',            'أقراص', '500 مجم'),
  ('Panadol Extra','باراسيتامول وكافيين',    'Paracetamol/Caffeine',   'أقراص', '500 مجم'),
  ('Adol',         'باراسيتامول',            'Paracetamol',            'أقراص', '500 مجم'),
  ('Abimol',       'باراسيتامول',            'Paracetamol',            'شراب',  '120 مجم/5 مل'),
  ('Cataflam',     'ديكلوفيناك بوتاسيوم',    'Diclofenac Potassium',   'أقراص', '50 مجم'),
  ('Voltaren',     'ديكلوفيناك صوديوم',      'Diclofenac Sodium',      'أمبول', '75 مجم'),
  ('Rofenac',      'ديكلوفيناك صوديوم',      'Diclofenac Sodium',      'أقراص', '50 مجم'),
  ('Brufen',       'إيبوبروفين',             'Ibuprofen',              'أقراص', '400 مجم'),
  ('Brufen',       'إيبوبروفين',             'Ibuprofen',              'شراب',  '100 مجم/5 مل'),
  ('Ketolac',      'كيتورولاك',              'Ketorolac',              'أمبول', '30 مجم'),
  ('Ketofan',      'كيتوبروفين',             'Ketoprofen',             'أقراص', '100 مجم'),
  ('Myofen',       'إيبوبروفين وباراسيتامول','Ibuprofen/Paracetamol',  'أقراص', ''),

  -- مضادات حيوية
  ('Augmentin',    'أموكسيسيللين وكلافولانيك','Amoxicillin/Clavulanate','أقراص','1 جم'),
  ('Augmentin',    'أموكسيسيللين وكلافولانيك','Amoxicillin/Clavulanate','شراب', '457 مجم/5 مل'),
  ('Hibiotic',     'أموكسيسيللين وكلافولانيك','Amoxicillin/Clavulanate','أقراص','1 جم'),
  ('Amoxil',       'أموكسيسيللين',           'Amoxicillin',            'كبسول','500 مجم'),
  ('Unictam',      'أمبيسيللين وسلباكتام',   'Ampicillin/Sulbactam',   'فيال', '1.5 جم'),
  ('Zithromax',    'أزيثرومايسين',           'Azithromycin',           'أقراص','500 مجم'),
  ('Zisrocin',     'أزيثرومايسين',           'Azithromycin',           'شراب', '200 مجم/5 مل'),
  ('Klaricid',     'كلاريثرومايسين',         'Clarithromycin',         'أقراص','500 مجم'),
  ('Ciprocin',     'سيبروفلوكساسين',         'Ciprofloxacin',          'أقراص','500 مجم'),
  ('Tavanic',      'ليفوفلوكساسين',          'Levofloxacin',           'أقراص','500 مجم'),
  ('Cefotax',      'سيفوتاكسيم',             'Cefotaxime',             'فيال', '1 جم'),
  ('Ceftriaxone',  'سيفترياكسون',            'Ceftriaxone',            'فيال', '1 جم'),
  ('Zinnat',       'سيفوروكسيم',             'Cefuroxime',             'أقراص','500 مجم'),
  ('Flagyl',       'ميترونيدازول',           'Metronidazole',          'أقراص','500 مجم'),
  ('Amrizole',     'ميترونيدازول',           'Metronidazole',          'شراب', '125 مجم/5 مل'),
  ('Doxymycin',    'دوكسيسيكلين',            'Doxycycline',            'كبسول','100 مجم'),

  -- الجهاز الهضمي
  ('Nexium',       'إيزوميبرازول',           'Esomeprazole',           'أقراص','40 مجم'),
  ('Controloc',    'بانتوبرازول',            'Pantoprazole',           'أقراص','40 مجم'),
  ('Omez',         'أوميبرازول',             'Omeprazole',             'كبسول','20 مجم'),
  ('Motilium',     'دومبيريدون',             'Domperidone',            'أقراص','10 مجم'),
  ('Primperan',    'ميتوكلوبراميد',          'Metoclopramide',         'أمبول','10 مجم'),
  ('Buscopan',     'هيوسين بيوتيل بروميد',   'Hyoscine Butylbromide',  'أقراص','10 مجم'),
  ('Spasmo-Digestin','إنزيمات هاضمة',        'Digestive Enzymes',      'أقراص',''),
  ('Antinal',      'نيفوروكسازيد',           'Nifuroxazide',           'كبسول','200 مجم'),
  ('Smecta',       'ديوسميكتيت',             'Diosmectite',            'أكياس','3 جم'),
  ('Duphalac',     'لاكتيولوز',              'Lactulose',              'شراب', '10 جم/15 مل'),
  ('Gaviscon',     'ألجينات الصوديوم',       'Sodium Alginate',        'شراب', ''),
  ('Epicogel',     'مضاد حموضة',             'Antacid',                'شراب', ''),
  ('Colona',       'ميبيفيرين',              'Mebeverine',             'كبسول','200 مجم'),

  -- الحساسية والجهاز التنفسي
  ('Telfast',      'فيكسوفينادين',           'Fexofenadine',           'أقراص','180 مجم'),
  ('Claritine',    'لوراتادين',              'Loratadine',             'أقراص','10 مجم'),
  ('Zyrtec',       'سيتريزين',               'Cetirizine',             'أقراص','10 مجم'),
  ('Allergyl',     'كلورفينيرامين',          'Chlorpheniramine',       'شراب', ''),
  ('Ventolin',     'سالبيوتامول',            'Salbutamol',             'بخاخ', '100 ميكروجم'),
  ('Ventolin',     'سالبيوتامول',            'Salbutamol',             'محلول بخار','5 مجم/مل'),
  ('Flixotide',    'فلوتيكازون',             'Fluticasone',            'بخاخ', '125 ميكروجم'),
  ('Symbicort',    'بوديزونيد وفورموتيرول',  'Budesonide/Formoterol',  'بخاخ', ''),
  ('Mucosolvan',   'أمبروكسول',              'Ambroxol',               'شراب', '30 مجم/5 مل'),
  ('Fluimucil',    'أسيتيل سيستئين',         'Acetylcysteine',         'أكياس','200 مجم'),
  ('Otrivin',      'زيلوميتازولين',          'Xylometazoline',         'نقط أنف',''),
  ('Congestal',    'مضاد احتقان',            'Decongestant',           'أقراص',''),

  -- القلب والضغط والدهون
  ('Concor',       'بيسوبرولول',             'Bisoprolol',             'أقراص','5 مجم'),
  ('Tritace',      'راميبريل',               'Ramipril',               'أقراص','5 مجم'),
  ('Norvasc',      'أملوديبين',              'Amlodipine',             'أقراص','5 مجم'),
  ('Capoten',      'كابتوبريل',              'Captopril',              'أقراص','25 مجم'),
  ('Lasix',        'فوروسيميد',              'Furosemide',             'أقراص','40 مجم'),
  ('Aspocid',      'أسبرين',                 'Aspirin',                'أقراص','75 مجم'),
  ('Plavix',       'كلوبيدوجريل',            'Clopidogrel',            'أقراص','75 مجم'),
  ('Lipitor',      'أتورفاستاتين',           'Atorvastatin',           'أقراص','20 مجم'),
  ('Crestor',      'روسوفاستاتين',           'Rosuvastatin',           'أقراص','10 مجم'),

  -- السكر والغدة
  ('Glucophage',   'ميتفورمين',              'Metformin',              'أقراص','850 مجم'),
  ('Amaryl',       'جليمبيريد',              'Glimepiride',            'أقراص','2 مجم'),
  ('Januvia',      'سيتاجليبتين',            'Sitagliptin',            'أقراص','100 مجم'),
  ('Lantus',       'إنسولين جلارجين',        'Insulin Glargine',       'قلم',  '100 وحدة/مل'),
  ('Mixtard',      'إنسولين مخلوط',          'Insulin Mixed',          'قلم',  '100 وحدة/مل'),
  ('Eltroxin',     'ليفوثيروكسين',           'Levothyroxine',          'أقراص','50 ميكروجم'),

  -- فيتامينات ومعادن
  ('Vidrop',       'فيتامين د',              'Vitamin D3',             'نقط', ''),
  ('Devarol-S',    'فيتامين د',              'Vitamin D3',             'أمبول','200000 وحدة'),
  ('Ossofortin',   'كالسيوم وفيتامين د',     'Calcium/Vitamin D',      'أقراص',''),
  ('Ferrofol',     'حديد وحمض فوليك',        'Iron/Folic Acid',        'كبسول',''),
  ('Neurorubine',  'فيتامين ب المركب',       'Vitamin B Complex',      'أقراص',''),
  ('Depovit B12',  'فيتامين ب ١٢',           'Vitamin B12',            'أمبول',''),
  ('Zincoral',     'زنك',                    'Zinc',                   'شراب', ''),

  -- الأعصاب والنفسية
  ('Lyrica',       'بريجابالين',             'Pregabalin',             'كبسول','75 مجم'),
  ('Neurontin',    'جابابنتين',              'Gabapentin',             'كبسول','300 مجم'),
  ('Depakine',     'صوديوم فالبروات',        'Sodium Valproate',       'أقراص','500 مجم'),
  ('Tegretol',     'كاربامازيبين',           'Carbamazepine',          'أقراص','200 مجم'),
  ('Cipralex',     'إيسيتالوبرام',           'Escitalopram',           'أقراص','10 مجم'),
  ('Prozac',       'فلوكسيتين',              'Fluoxetine',             'كبسول','20 مجم'),
  ('Xanax',        'ألبرازولام',             'Alprazolam',             'أقراص','0.5 مجم'),
  ('Mydocalm',     'تولبيريزون',             'Tolperisone',            'أقراص','150 مجم'),
  ('Myogesic',     'مرخي عضلات ومسكن',       'Muscle Relaxant',        'أقراص',''),

  -- كورتيزون وإنزيمات وموضعي
  ('Solu-Medrol',  'ميثيل بريدنيزولون',      'Methylprednisolone',     'فيال', '40 مجم'),
  ('Hydrocortisone','هيدروكورتيزون',         'Hydrocortisone',         'فيال', '100 مجم'),
  ('Alphintern',   'إنزيمات مضادة للالتهاب', 'Trypsin/Chymotrypsin',   'أقراص',''),
  ('Fucidin',      'حمض الفيوسيديك',         'Fusidic Acid',           'كريم', ''),
  ('Fucicort',     'فيوسيديك وبيتاميثازون',  'Fusidic/Betamethasone',  'كريم', ''),
  ('Kenacomb',     'مرهم مركب',              'Combination Ointment',   'مرهم', ''),
  ('Canesten',     'كلوتريمازول',            'Clotrimazole',           'كريم', ''),
  ('Diflucan',     'فلوكونازول',             'Fluconazole',            'كبسول','150 مجم'),
  ('Nystatin',     'نيستاتين',               'Nystatin',               'معلق', ''),
  ('Zovirax',      'أسيكلوفير',              'Aciclovir',              'أقراص','400 مجم'),

  -- المسالك والنساء
  ('Uvamin',       'نيتروفورانتوين',         'Nitrofurantoin',         'كبسول','100 مجم'),
  ('Rowatinex',    'زيوت طيارة',             'Terpene Combination',    'كبسول',''),
  ('Duphaston',    'ديدروجستيرون',           'Dydrogesterone',         'أقراص','10 مجم'),
  ('Cyclo-Progynova','هرمونات بديلة',        'Estradiol/Norgestrel',   'أقراص','')
on conflict (trade_name, strength, form_ar) do nothing;

-- ---------------------------------------------------------------------------
--  الأسماء التجارية بالعربي
--
--  ⚠ THIS BLOCK IS NOT COSMETIC. Egyptian doctors prescribe by brand, and many
--    of them type Arabic. Without these spellings the search box answers
--    "كونكور" with nothing while holding Concor, and "فلاجيل" with nothing
--    while holding Flagyl — the drug is in the catalogue and simply cannot be
--    found by the words the doctor used.
--
--  Kept as a separate UPDATE rather than a sixth column on the INSERT above so
--  that the list reads as what it is: a spelling map, extendable one line at a
--  time by whoever notices a name that will not come up.
-- ---------------------------------------------------------------------------
update clinic.drugs d set trade_name_ar = v.ar
  from (values
    ('Panadol','بانادول'), ('Panadol Extra','بانادول إكسترا'), ('Adol','أدول'),
    ('Abimol','أبيمول'), ('Cataflam','كتافلام'), ('Voltaren','فولتارين'),
    ('Rofenac','روفيناك'), ('Brufen','بروفين'), ('Ketolac','كيتولاك'),
    ('Ketofan','كيتوفان'), ('Myofen','مايوفين'),

    ('Augmentin','أوجمنتين'), ('Hibiotic','هاي بيوتك'), ('Amoxil','أموكسيل'),
    ('Unictam','يونيكتام'), ('Zithromax','زيثروماكس'), ('Zisrocin','زيسروسين'),
    ('Klaricid','كلاريسيد'), ('Ciprocin','سيبروسين'), ('Tavanic','تافانيك'),
    ('Cefotax','سيفوتاكس'), ('Ceftriaxone','سيفترياكسون'), ('Zinnat','زينات'),
    ('Flagyl','فلاجيل'), ('Amrizole','أمريزول'), ('Doxymycin','دوكسيميسين'),

    ('Nexium','نيكسيوم'), ('Controloc','كونترولوك'), ('Omez','أوميز'),
    ('Motilium','موتيليوم'), ('Primperan','بريمبران'), ('Buscopan','بوسكوبان'),
    ('Spasmo-Digestin','سبازمو ديچستين'), ('Antinal','أنتينال'),
    ('Smecta','سميكتا'), ('Duphalac','دوفالاك'), ('Gaviscon','جافيسكون'),
    ('Epicogel','إبيكوجيل'), ('Colona','كولونا'),

    ('Telfast','تلفاست'), ('Claritine','كلاريتين'), ('Zyrtec','زيرتك'),
    ('Allergyl','أليرجيل'), ('Ventolin','فنتولين'), ('Flixotide','فليكسوتايد'),
    ('Symbicort','سيمبيكورت'), ('Mucosolvan','ميوكوسولفان'),
    ('Fluimucil','فلوموسيل'), ('Otrivin','أوتريفين'), ('Congestal','كونجستال'),

    ('Concor','كونكور'), ('Tritace','تريتاس'), ('Norvasc','نورفاسك'),
    ('Capoten','كابوتين'), ('Lasix','لازيكس'), ('Aspocid','أسبوسيد'),
    ('Plavix','بلافكس'), ('Lipitor','ليبيتور'), ('Crestor','كريستور'),

    ('Glucophage','جلوكوفاج'), ('Amaryl','أماريل'), ('Januvia','جانوفيا'),
    ('Lantus','لانتوس'), ('Mixtard','ميكستارد'), ('Eltroxin','إلتروكسين'),

    ('Vidrop','فيدروب'), ('Devarol-S','ديفارول'), ('Ossofortin','أوسوفورتين'),
    ('Ferrofol','فيروفول'), ('Neurorubine','نيوروروبين'),
    ('Depovit B12','ديبوفيت'), ('Zincoral','زنكورال'),

    ('Lyrica','ليريكا'), ('Neurontin','نيورونتين'), ('Depakine','ديباكين'),
    ('Tegretol','تيجريتول'), ('Cipralex','سيبرالكس'), ('Prozac','بروزاك'),
    ('Xanax','زاناكس'), ('Mydocalm','ميدوكالم'), ('Myogesic','مايوجيسك'),

    ('Solu-Medrol','سولومدرول'), ('Hydrocortisone','هيدروكورتيزون'),
    ('Alphintern','ألفنترن'), ('Fucidin','فيوسيدين'), ('Fucicort','فيوسيكورت'),
    ('Kenacomb','كيناكومب'), ('Canesten','كانستين'), ('Diflucan','ديفلوكان'),
    ('Nystatin','نيستاتين'), ('Zovirax','زوفيراكس'),

    ('Uvamin','يوفامين'), ('Rowatinex','رواتينكس'), ('Duphaston','دوفاستون'),
    ('Cyclo-Progynova','سيكلو بروجينوفا')
  ) as v(name, ar)
 where d.trade_name = v.name and d.trade_name_ar = '';

-- ---------------------------------------------------------- تحاليل وأشعة ----
insert into clinic.lab_tests (name_ar, name_en, category) values
  ('صورة دم كاملة',            'CBC',                    'تحاليل'),
  ('سرعة الترسيب',             'ESR',                    'تحاليل'),
  ('بروتين سي التفاعلي',       'CRP',                    'تحاليل'),
  ('سكر صائم',                 'Fasting Blood Sugar',    'تحاليل'),
  ('سكر بعد الأكل بساعتين',    'Post-Prandial Sugar',    'تحاليل'),
  ('السكر التراكمي',           'HbA1c',                  'تحاليل'),
  ('وظائف كبد',                'Liver Function Tests',   'تحاليل'),
  ('وظائف كلى',                'Kidney Function Tests',  'تحاليل'),
  ('دهون كاملة',               'Lipid Profile',          'تحاليل'),
  ('حمض بوليك',                'Uric Acid',              'تحاليل'),
  ('وظائف غدة درقية',          'TSH / T3 / T4',          'تحاليل'),
  ('تحليل بول',                'Urine Analysis',         'تحاليل'),
  ('تحليل براز',               'Stool Analysis',         'تحاليل'),
  ('مزرعة بول',                'Urine Culture',          'تحاليل'),
  ('فيتامين د',                'Vitamin D (25-OH)',      'تحاليل'),
  ('فيتامين ب ١٢',             'Vitamin B12',            'تحاليل'),
  ('مخزون الحديد',             'Serum Ferritin',         'تحاليل'),
  ('صوديوم وبوتاسيوم',         'Serum Electrolytes',     'تحاليل'),
  ('أشعة عادية على الصدر',     'Chest X-Ray',            'أشعة'),
  ('أشعة عادية على البطن',     'Abdominal X-Ray',        'أشعة'),
  ('سونار على البطن والحوض',   'Abdominopelvic US',      'أشعة'),
  ('سونار على الغدة الدرقية',  'Thyroid US',             'أشعة'),
  ('دوبلر على الشرايين',       'Arterial Doppler',       'أشعة'),
  ('أشعة مقطعية',              'CT Scan',                'أشعة'),
  ('رنين مغناطيسي',            'MRI',                    'أشعة'),
  ('رسم قلب',                  'ECG',                    'وظائف'),
  ('إيكو على القلب',           'Echocardiography',       'وظائف'),
  ('وظائف تنفس',               'Spirometry',             'وظائف')
on conflict (name_ar, category) do nothing;

-- ---------------------------------------------------------------- grants ---

revoke execute on function clinic.drug_catalog(timestamptz)              from public, anon;
revoke execute on function clinic.add_drug(text, text, text, text, text) from public, anon;
revoke execute on function clinic.bump_catalog_version()                 from public, anon;

grant execute on function clinic.drug_catalog(timestamptz)        to authenticated;
grant execute on function clinic.add_drug(text, text, text, text, text) to authenticated;

-- ## 20260812100006_clinic_accounts.sql
-- ============================================================================
--  العيادة — الحسابات
--
--  ⚠  Sorts AFTER 20260810100006_rls.sql. Carries its own grants, at the
--     bottom.
--
--  Reuses public.create_account() rather than repeating it. That function
--  carries three traps that cost real time in a sibling project — GoTrue's
--  NOT-NULL token columns, the missing auth.identities row, and crypt() living
--  in `extensions` on hosted Supabase — and a second copy here would be a
--  second copy of those bugs waiting to be reintroduced.
--
--  It is REVOKED from every role, which is deliberate: it takes the role as an
--  argument, so a grant would be a way to mint a manager. The wrappers below
--  reach it anyway because SECURITY DEFINER runs them as the owner, which is
--  the same door public.admin_create_user() goes through.
--
--  NOTE ON THE SHOP ROLE. Clinic staff are created with public role
--  'customer' — meaning "no role in the SHOP". A doctor is not a shop manager
--  and must never reach /admin. Their real role is clinic.staff.role, and that
--  is the only role any policy in this schema reads.
-- ============================================================================

create or replace function clinic.create_staff(
  p_phone        text,
  p_full_name    text,
  p_password     text,
  p_role         clinic.staff_role,
  p_display_name text default null,
  p_title_ar     text default null,
  p_specialty_ar text default null,
  p_syndicate_no text default null,
  p_rx_prefix    text default null
) returns uuid
language plpgsql security definer set search_path = clinic, public as $$
declare
  v_id     uuid;
  v_prefix text := nullif(trim(coalesce(p_rx_prefix,'')), '');
  v_n      int;
begin
  if not clinic.is_director() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;

  -- Raises BAD_PHONE / NAME_REQUIRED / PASSWORD_TOO_SHORT / PHONE_TAKEN, and
  -- the clinic's error map translates them with the same wording the shop
  -- uses.
  v_id := public.create_account(p_phone, p_full_name, p_password, 'customer');

  if p_role <> 'reception' and v_prefix is null then
    -- Short, unique, and it prints inside a prescription number a pharmacist
    -- reads over the phone. Sequential rather than derived from the name: two
    -- doctors called أحمد would otherwise collide on their first day.
    select count(*) + 1 into v_n from clinic.staff where role in ('doctor','director');
    v_prefix := 'د' || v_n::text;
    while exists (select 1 from clinic.staff where rx_prefix = v_prefix) loop
      v_n := v_n + 1;
      v_prefix := 'د' || v_n::text;
    end loop;
  end if;

  insert into clinic.staff (
    id, role, display_name, title_ar, specialty_ar, syndicate_no, rx_prefix
  ) values (
    v_id, p_role,
    coalesce(nullif(trim(coalesce(p_display_name,'')), ''), trim(p_full_name)),
    nullif(trim(coalesce(p_title_ar,'')), ''),
    nullif(trim(coalesce(p_specialty_ar,'')), ''),
    nullif(trim(coalesce(p_syndicate_no,'')), ''),
    v_prefix
  );

  insert into clinic.audit_events (actor_id, action, entity, entity_id, detail)
  values (auth.uid(), 'created_staff', 'staff', v_id,
          jsonb_build_object('role', p_role::text));

  return v_id;
end $$;

-- ---------------------------------------------------------------------------
--  إيقاف حساب
--
--  Same two guards as public.admin_set_active(), for the same two reasons:
--  switching yourself off locks you out of your own clinic, and switching off
--  the last director leaves nobody who can switch anyone back on.
-- ---------------------------------------------------------------------------
create or replace function clinic.set_staff_active(p_id uuid, p_active boolean)
returns void
language plpgsql security definer set search_path = clinic, public as $$
begin
  if not clinic.is_director() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if p_id = auth.uid() then
    raise exception 'CANNOT_DISABLE_SELF' using errcode = 'P0001';
  end if;
  if not p_active and (
       select count(*) from clinic.staff
        where role = 'director' and is_active and id <> p_id) = 0 then
    raise exception 'LAST_DIRECTOR' using errcode = 'P0001';
  end if;

  update clinic.staff set is_active = p_active where id = p_id;
end $$;

-- A director resetting a doctor's password, or anyone changing their own.
-- public.admin_set_password() cannot serve this: it asks is_manager(), and a
-- director of the clinic is deliberately not a manager of the shop.
create or replace function clinic.set_staff_password(p_id uuid, p_password text)
returns void
language plpgsql security definer set search_path = clinic, public, extensions as $$
begin
  if not (clinic.is_director() or p_id = auth.uid()) then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if not exists (select 1 from clinic.staff where id = p_id) then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if length(coalesce(p_password, '')) < 6 then
    raise exception 'PASSWORD_TOO_SHORT' using errcode = 'P0001';
  end if;

  update auth.users
     set encrypted_password = crypt(p_password, gen_salt('bf')),
         updated_at = now()
   where id = p_id;

  perform public.fix_auth_user_tokens(p_id);
end $$;

-- The staff screen. Joins the phone off the profile, because that is the
-- username people sign in with and the director needs to read it back to
-- somebody who has forgotten it.
create or replace function clinic.staff_list()
returns table (
  id uuid, role clinic.staff_role, display_name text, phone text,
  title_ar text, specialty_ar text, syndicate_no text, rx_prefix text,
  is_active boolean, created_at timestamptz
)
language sql stable security definer set search_path = clinic, public as $$
  select s.id, s.role, s.display_name, p.phone,
         s.title_ar, s.specialty_ar, s.syndicate_no, s.rx_prefix,
         s.is_active, s.created_at
    from clinic.staff s
    join public.profiles p on p.id = s.id
   where clinic.is_director()
   order by s.role, s.display_name
$$;

-- Who am I, in one call the shell can make on load. Returns null for a signed
-- in user who does not work here — which is what the shop's own manager gets,
-- and correctly so.
create or replace function clinic.me()
returns jsonb
language sql stable security definer set search_path = clinic, public as $$
  select to_jsonb(s) || jsonb_build_object('phone', p.phone)
    from clinic.staff s
    join public.profiles p on p.id = s.id
   where s.id = auth.uid() and s.is_active
$$;

-- ---------------------------------------------------------------- grants ---

revoke execute on function clinic.create_staff(text, text, text, clinic.staff_role,
                                               text, text, text, text, text) from public, anon;
revoke execute on function clinic.set_staff_active(uuid, boolean)   from public, anon;
revoke execute on function clinic.set_staff_password(uuid, text)    from public, anon;
revoke execute on function clinic.staff_list()                      from public, anon;
revoke execute on function clinic.me()                              from public, anon;

grant execute on function clinic.create_staff(text, text, text, clinic.staff_role,
                                              text, text, text, text, text) to authenticated;
grant execute on function clinic.set_staff_active(uuid, boolean)   to authenticated;
grant execute on function clinic.set_staff_password(uuid, text)    to authenticated;
grant execute on function clinic.staff_list()                      to authenticated;
grant execute on function clinic.me()                              to authenticated;

-- ============================================================================
--  أول حساب ديريكتور
--
--  الموبايل 01000000009 وكلمة السر تحت.
--  ⚠  غيّر كلمة السر أول ما تدخل — الملف ده موجود في المستودع، فأي حد يقراه
--     يعرف كلمة السر دي. ودي بيانات مرضى.
--
--  Bypasses clinic.create_staff() because that one asks is_director(), and at
--  this instant there is nobody to be one.
--
--  ⚠ RESERVED SEED NUMBERS — profiles.phone is UNIQUE, so a collision here
--   fails the whole install with a constraint error nobody can read:
--     01000000000  the shop's first manager   (20260810100011_accounts.sql)
--     01000000001  the harness's test manager (tools/schema-check/verify.mjs)
--     01000000002  the harness's test customer
--     01000000009  ← this one
--
--  Re-runnable: a second run finds a director already there and does nothing.
-- ============================================================================
do $$
declare v_id uuid;
begin
  if not exists (select 1 from clinic.staff where role = 'director') then
    v_id := public.create_account('01000000009', 'مدير العيادة', 'clinic2026', 'customer');
    insert into clinic.staff (id, role, display_name, title_ar, rx_prefix)
    values (v_id, 'director', 'د. مدير العيادة', 'استشاري', 'د1')
    on conflict (id) do nothing;
  end if;
end $$;

-- ## seed.sql
-- ============================================================================
--  بيانات البداية — نكست كامباين
--
--  Re-runnable. Every insert carries an `on conflict do nothing`, so pasting
--  this a second time changes nothing.
--
--  The products here are REAL shapes with plausible Egyptian pricing, not
--  lorem ipsum — a catalogue you cannot browse honestly is a catalogue you
--  cannot judge. Replace the prices with yours before going live; the ones
--  marked موديل تجريبي in short_pitch_ar are meant to be deleted.
--
--  Note the order at the bottom: products are inserted UNPUBLISHED, then
--  published only after their tiers, methods and positions exist. That is the
--  publish gate in 20260810100003_pricing.sql doing its job, and the seed is
--  the first thing that proves it works.
-- ============================================================================

-- ------------------------------------------------------------- الفئات ------

insert into public.categories (slug, name_ar, name_en, blurb_ar, icon, sort_order) values
  ('mugs',       'مجات وأكواب',        'Mugs',        'سيراميك وسحري وترمس — أكتر هدية بتفضل على المكتب',      'coffee',   10),
  ('bottles',    'زجاجات وترمس',       'Bottles',     'ستانلس وتريتان، للجيم والمكتب والرحلات',                 'bottle',   20),
  ('pens',       'أقلام',              'Pens',        'من القلم الدعائي للطقم الفاخر بعلبته',                    'pen',      30),
  ('notebooks',  'نوتات وأجندات',      'Notebooks',   'أجندات جلد ونوتات سلك بمقاسات المكتب',                   'notebook', 40),
  ('apparel',    'ملابس',              'Apparel',     'تيشرتات وبولو وكابات بالتطريز أو الطباعة',                'shirt',    50),
  ('tech',       'هدايا تكنولوجية',    'Tech gifts',  'فلاشات وباور بانك وماوس باد',                            'usb',      60),
  ('bags',       'شنط',                'Bags',        'توتال قماش وشنط لابتوب',                                  'bag',      70),
  ('desk',       'مستلزمات مكتب',      'Desk',        'حوامل ومنظمات وأطقم مكتب',                                'desk',     80),
  ('keychains',  'ميداليات',           'Keychains',   'معدن وجلد وأكريليك',                                      'key',      90),
  ('clocks',     'ساعات حائط',         'Wall clocks', 'ساعات بلوجو الشركة للمقر والفروع',                        'clock',   100),
  ('giftbox',    'علب هدايا',          'Gift boxes',  'بوكسات مجمّعة للمناسبات',                                 'gift',    110),
  ('printing',   'مطبوعات',            'Printing',    'كروت وبروشور وفواتير وأكياس',                             'print',   120)
on conflict (slug) do nothing;

-- ---------------------------------------------------------- المناسبات ------

insert into public.occasions (slug, name_ar, name_en, blurb_ar, sort_order) values
  ('ramadan',     'رمضان',            'Ramadan',      'بوكسات وهدايا رمضان للموظفين والعملاء', 10),
  ('eid',         'العيد',            'Eid',          'معايدات وهدايا العيد',                  20),
  ('new-year',    'رأس السنة',        'New Year',     'أجندات وهدايا بداية السنة',             30),
  ('birthday',    'عيد ميلاد',        'Birthday',     'هدية باسم صاحبها',                      40),
  ('graduation',  'تخرج',             'Graduation',   'هدايا التخرج والدفعات',                 50),
  ('opening',     'افتتاح',           'Opening',      'هدايا افتتاح الفروع',                   60),
  ('conference',  'مؤتمرات ومعارض',   'Conferences',  'حقائب ونوتات وأقلام للزوار',            70),
  ('love',        'كلمة حب',          'Love note',    'هدية عليها كلمة مش موجودة عند حد تاني',  80),
  ('mothers-day', 'عيد الأم',         'Mother''s Day','هدايا عيد الأم',                         90)
on conflict (slug) do nothing;

-- ------------------------------------------------------ طرق الطباعة ------

insert into public.print_methods
  (code, name_ar, name_en, blurb_ar, color_model, needs_vector, default_setup_fee, default_max_colors, sort_order) values
  ('screen','سلك سكرين','Screen printing',
   'الأقوى والأرخص في الكميات الكبيرة. بتدفع كليشيه لكل لون مرة واحدة.',
   'spot', true, 150, 4, 10),
  ('pad','باد / تامبو','Pad printing',
   'للأسطح الصغيرة والمنحنية زي جسم القلم وودن الكوباية.',
   'spot', true, 120, 2, 20),
  ('laser','حفر ليزر','Laser engraving',
   'بيحفر في الخامة نفسها — مالوش لون، وعمره ما بيمسح.',
   'single_tone', true, 0, null, 30),
  ('embroidery','تطريز','Embroidery',
   'للملابس والكابات والشنط. رسم الديچيتايزنج مرة واحدة على التصميم.',
   'thread', true, 250, 8, 40),
  ('sublimation','سبليميشن','Sublimation',
   'ألوان كاملة على السيراميك والبوليستر. سعر واحد مهما كان عدد الألوان.',
   'full_color', false, 0, null, 50),
  ('uv','طباعة UV','UV printing',
   'ألوان كاملة على أي سطح تقريباً، بحبر بيجف بالأشعة.',
   'full_color', false, 100, null, 60),
  ('dtf','طباعة DTF','DTF',
   'ألوان كاملة على الملابس القطن والبوليستر، من غير حد أدنى للألوان.',
   'full_color', false, 0, null, 70),
  ('transfer','ترانسفير','Heat transfer',
   'للكميات الصغيرة والتصميمات المتغيرة.',
   'full_color', false, 0, null, 80),
  ('digital','طباعة ديچيتال','Digital printing',
   'للمطبوعات الورقية بكميات صغيرة ومتوسطة.',
   'full_color', false, 0, null, 90),
  ('foil','فويل ذهبي/فضي','Foil stamping',
   'ختم معدني لامع — للكروت والعلب الفاخرة.',
   'single_tone', true, 200, null, 100),
  ('emboss','بارز / إمبوس','Embossing',
   'نقش بارز من غير حبر. بيتحس بالإيد قبل ما يتشاف.',
   'single_tone', true, 350, null, 110)
on conflict (code) do nothing;

-- ------------------------------------------------------------ الخطوط ------

insert into public.fonts (key, name_ar, name_en, css_family, script, is_display, sort_order) values
  ('cairo',      'القاهرة',    'Cairo',      'Cairo',       'both',   false, 10),
  ('tajawal',    'تجوّل',      'Tajawal',    'Tajawal',     'both',   false, 20),
  ('almarai',    'المراعي',    'Almarai',    'Almarai',     'arabic', false, 30),
  ('amiri',      'أميري',      'Amiri',      'Amiri',       'arabic', true,  40),
  ('reem-kufi',  'ريم كوفي',   'Reem Kufi',  'Reem Kufi',   'arabic', true,  50),
  ('aref-ruqaa', 'عارف رقعة',  'Aref Ruqaa', 'Aref Ruqaa',  'arabic', true,  60),
  ('lemonada',   'ليمونادة',   'Lemonada',   'Lemonada',    'arabic', true,  70),
  ('changa',     'شنجة',       'Changa',     'Changa',      'arabic', true,  80),
  ('montserrat', 'مونتسيرات',  'Montserrat', 'Montserrat',  'latin',  false, 90)
on conflict (key) do nothing;

-- ------------------------------------------------- كتالوج المواصفات ------

insert into public.spec_defs
  (key, label_ar, unit_ar, kind, higher_is_better, is_filterable, show_in_card, is_key, section_ar, sort_order) values
  ('material_ar',     'الخامة',            null,   'text',   null,  false, true,  true,  'الأساسي',   10),
  ('dimensions_ar',   'المقاس',            null,   'text',   null,  false, false, true,  'الأساسي',   20),
  ('weight_g',        'الوزن',             'جرام', 'number', null,  false, false, false, 'الأساسي',   30),
  ('capacity_ml',     'السعة',             'مل',   'number', true,  true,  true,  true,  'الأساسي',   40),
  ('paper_gsm',       'جراماج الورق',      'جم/م²','number', true,  true,  false, true,  'الورق',     50),
  ('page_count',      'عدد الصفحات',       'صفحة', 'number', true,  true,  true,  true,  'الورق',     60),
  ('usb_capacity_gb', 'سعة الفلاشة',       'جيجا', 'number', true,  true,  true,  true,  'التقنية',   70),
  ('battery_mah',     'سعة البطارية',      'mAh',  'number', true,  true,  true,  true,  'التقنية',   80),
  ('pack_size',       'عدد القطع بالعبوة', 'قطعة', 'number', null,  false, false, false, 'التغليف',   90),
  ('warranty_months', 'الضمان',            'شهر',  'number', true,  false, false, false, 'الضمان',   100),
  ('origin_ar',       'بلد المنشأ',        null,   'text',   null,  true,  false, false, 'الأساسي',  110),
  ('is_eco',          'خامة صديقة للبيئة', null,   'bool',   true,  true,  false, false, 'الأساسي',  120)
on conflict (key) do nothing;

-- Scoping. Remember the convention: NO rows here = applies to every category.
-- So material_ar, dimensions_ar, weight_g, origin_ar and is_eco are absent on
-- purpose — they are asked about every product.
insert into public.spec_def_categories (spec_key, category_id)
select v.spec_key, c.id
  from (values
    ('capacity_ml','mugs'), ('capacity_ml','bottles'),
    ('paper_gsm','notebooks'), ('paper_gsm','printing'),
    ('page_count','notebooks'),
    ('usb_capacity_gb','tech'),
    ('battery_mah','tech'),
    ('warranty_months','tech'), ('warranty_months','clocks'),
    ('pack_size','pens'), ('pack_size','printing'), ('pack_size','keychains')
  ) as v(spec_key, cat_slug)
  join public.categories c on c.slug = v.cat_slug
on conflict do nothing;

-- ---------------------------------------------------------- المنتجات ------
--
-- Inserted UNPUBLISHED. Published at the very bottom, once the tiers, methods
-- and positions each product needs actually exist.

insert into public.products (
  slug, category_id, sku, name_ar, name_en, short_pitch_ar, description_ar,
  for_corporate, for_individual, moq, max_positions, max_text_lines,
  allows_logo, allows_text, lead_days_min, lead_days_max,
  material_ar, dimensions_ar, weight_g, capacity_ml, paper_gsm, page_count,
  usb_capacity_gb, battery_mah, pack_size, warranty_months, origin_ar, is_eco,
  sort_order
)
select
  v.slug, c.id, v.sku, v.name_ar, v.name_en, v.pitch, v.descr,
  v.corp::boolean, v.indiv::boolean, v.moq::int, v.max_pos::int, v.max_lines::int,
  v.logo::boolean, v.txt::boolean, v.lead_min::int, v.lead_max::int,
  v.material, v.dims, v.weight::int, v.capacity::int, v.gsm::int, v.pages::int,
  v.usb::int, v.mah::int, v.pack::int, v.warranty::int, v.origin, v.eco::boolean,
  v.sort::int
from (values
  -- ---- مجات وأكواب ----
  ('mug-ceramic-white','mugs','NC-MUG-01','مج سيراميك أبيض','White ceramic mug',
   'أشهر هدية دعائية على الإطلاق — وأرخص تكلفة للقطعة في الكميات الكبيرة.',
   'مج سيراميك درجة أولى، سعة ٣٣٠ مل، يتحمل غسالة الأطباق والميكروويف. الطباعة سبليميشن بألوان كاملة على وش واحد أو الاتنين. أنسب اختيار لهدايا المؤتمرات وأطقم الترحيب بالموظفين الجدد.',
   true,false,36,2,2,true,true,3,5,'سيراميك','9.5 × 8 سم',320,330,null,null,null,null,null,null,'الصين',false,10),

  ('mug-magic-color','mugs','NC-MUG-02','مج سحري بيتغير لونه','Magic colour-change mug',
   'أسود وهو فاضي، وبيكشف التصميم لما تصب فيه حاجة سخنة.',
   'مج سحري بطبقة حرارية: التصميم بيظهر عند ٤٥ درجة وبيختفي لما يبرد. بيعمل انطباع قوي في هدايا العملاء وبيتصوّر كتير على السوشيال. الطباعة سبليميشن فقط.',
   true,true,24,1,2,true,true,4,7,'سيراميك بطبقة حرارية','9.5 × 8 سم',340,330,null,null,null,null,null,null,'الصين',false,20),

  ('mug-travel-steel','mugs','NC-MUG-03','ترمس سفر ستانلس','Steel travel mug',
   'بيحافظ على السخونة ٦ ساعات، وبيتحفر بالليزر فيفضل مدى الحياة.',
   'ترمس ستانلس ٣٠٤ مزدوج الجدار بغطاء محكم، سعة ٤٥٠ مل. الحفر بالليزر بيدي شكل راقي ومش بيمسح مع الغسيل. مناسب لهدايا الإدارة العليا.',
   true,false,25,1,2,true,true,5,8,'ستانلس ستيل 304','19 × 7 سم',290,450,null,null,null,null,null,null,'الصين',false,30),

  ('mug-name-gift','mugs','NC-MUG-04','مج باسمك — هدية','Personalised name mug',
   'قطعة واحدة، باسمها أو بكلمة انت اللي تكتبها.',
   'نفس المج السيراميك، بس معمول لهدية شخصية: اكتب الاسم أو كلمة الحب أو المعايدة، اختار الخط، وشوف الشكل قبل ما تطلب. بنسلّمه في علبة هدية.',
   false,true,1,2,3,false,true,2,4,'سيراميك','9.5 × 8 سم',320,330,null,null,null,null,null,null,'الصين',false,40),

  -- ---- زجاجات ----
  ('bottle-steel-750','bottles','NC-BTL-01','زجاجة ستانلس ٧٥٠ مل','Steel bottle 750ml',
   'للجيم والمكتب — والحفر عليها بيعيش أطول من الوظيفة.',
   'زجاجة ستانلس مزدوجة الجدار بغطاء رياضي، ٧٥٠ مل. بتحافظ على البرودة ١٢ ساعة. الحفر بالليزر على جسم الزجاجة.',
   true,false,25,1,2,true,true,5,8,'ستانلس ستيل 304','26 × 7 سم',390,750,null,null,null,null,null,null,'الصين',false,50),

  ('bottle-tritan-700','bottles','NC-BTL-02','زجاجة تريتان شفافة','Tritan bottle 700ml',
   'خفيفة وشفافة، والطباعة عليها بتبان من بعيد.',
   'زجاجة تريتان خالية من BPA، ٧٠٠ مل، بغطاء لولبي ومقبض. أنسب للفعاليات الرياضية وهدايا الطلبة. طباعة سلك سكرين أو UV.',
   true,false,50,1,2,true,true,4,7,'تريتان','24 × 6.5 سم',120,700,null,null,null,null,null,null,'الصين',true,60),

  -- ---- أقلام ----
  ('pen-metal-classic','pens','NC-PEN-01','قلم معدن كلاسيك','Classic metal pen',
   'وزنه في الإيد هو اللي بيفرق — والحفر بالليزر بيبان فضي على الأسود.',
   'قلم جاف معدني بآلية ضغط، حبر أزرق ألماني، جسم مطلي. الحفر بالليزر بيكشف لون المعدن تحت الطلاء. بيتسلّم في علبة كرتون أو مخمل حسب الطلب.',
   true,false,100,1,1,true,true,4,7,'معدن مطلي','14 سم',28,null,null,null,null,null,1,null,'الصين',false,70),

  ('pen-plastic-promo','pens','NC-PEN-02','قلم بلاستيك دعائي','Promo plastic pen',
   'أرخص حاجة بتوصّل اسمك لأكبر عدد ناس.',
   'قلم بلاستيك خفيف بحبر أزرق، متاح بألوان جسم متعددة. طباعة باد على الجسم أو الكليب. الاختيار الأول لتوزيعات المعارض.',
   true,false,250,2,1,true,true,3,6,'بلاستيك ABS','14 سم',9,null,null,null,null,null,1,null,'مصر',false,80),

  ('pen-set-gift','pens','NC-PEN-03','طقم قلم فاخر بعلبة','Gift pen set',
   'قلم جاف وحبر سائل في علبة مخمل — هدية الاجتماع المهم.',
   'طقم من قطعتين (جاف + حبر سائل) في علبة مخمل بقفل مغناطيسي. الحفر بالليزر على القلمين وعلى بلاكة العلبة.',
   true,true,25,2,2,true,true,6,10,'معدن + علبة مخمل','17 × 6 سم',180,null,null,null,null,null,2,null,'الصين',false,90),

  -- ---- نوتات ----
  ('notebook-a5-pu','notebooks','NC-NTB-01','أجندة A5 جلد صناعي','A5 PU notebook',
   'الأجندة اللي بتفضل على المكتب سنة كاملة وعليها لوجوك.',
   'أجندة مقاس A5 بغلاف جلد صناعي وحزام مطاطي وفاصل شريطي، ١٩٢ صفحة ورق ٨٠ جرام مسطّر. اللوجو بالحفر البارز أو الطباعة الحرارية على الغلاف.',
   true,false,50,1,2,true,true,6,10,'جلد صناعي','21 × 14.5 سم',420,null,80,192,null,null,null,null,'الصين',false,100),

  ('notebook-spiral-a4','notebooks','NC-NTB-02','نوتة سلك A4','A4 spiral notebook',
   'للتدريب والمؤتمرات — بتتفتح على الطربيزة وبتفضل مفتوحة.',
   'نوتة سلك معدني مقاس A4، ١٠٠ ورقة ٧٠ جرام، غلاف كوشيه مقوى. الغلاف بيتطبع بالكامل بألوان كاملة — مساحة إعلانية كاملة مش مجرد لوجو.',
   true,false,100,1,2,true,true,5,9,'كرتون كوشيه مقوى','29.7 × 21 سم',380,null,70,100,null,null,null,null,'مصر',true,110),

  -- ---- ملابس ----
  ('tshirt-cotton-round','apparel','NC-APP-01','تيشرت قطن نص كم','Cotton round-neck tee',
   'قطن ١٨٠ جرام — مش التيشرت اللي بيتكرمش بعد أول غسلة.',
   'تيشرت قطن ١٠٠٪ بوزن ١٨٠ جرام/م²، ياقة مستديرة مضلعة، مقاسات من S لـ 3XL. متاح بالطباعة DTF بألوان كاملة أو التطريز على الصدر.',
   true,false,24,3,2,true,true,5,9,'قطن 100% — 180 جم','حسب المقاس',180,null,null,null,null,null,null,null,'مصر',true,120),

  ('polo-pique','apparel','NC-APP-02','بولو بيكيه','Piqué polo shirt',
   'زي الفريق اللي بيقابل العميل.',
   'بولو بيكيه قطن/بوليستر بياقة وأزرار، مقاسات S–3XL، ألوان متعددة. التطريز على الصدر الشمال هو الاختيار المعتاد ليونيفورم الشركات.',
   true,false,24,2,1,true,true,7,12,'بيكيه 65% قطن','حسب المقاس',220,null,null,null,null,null,null,null,'مصر',false,130),

  ('cap-baseball','apparel','NC-APP-03','كاب بيسبول','Baseball cap',
   'التطريز عليه بيبان من مسافة عشرين متر.',
   'كاب ٦ قطع بحزام خلفي قابل للضبط، قطن مبروش. التطريز الأمامي حتى ٨ ألوان خيط.',
   true,false,50,2,1,true,false,6,10,'قطن مبروش','مقاس واحد',85,null,null,null,null,null,null,null,'الصين',false,140),

  -- ---- تكنولوجيا ----
  ('usb-metal-flip','tech','NC-TEC-01','فلاشة معدن قلاب','Metal flip USB',
   'هدية بتفضل في جيب العميل — وعليها لوجوك محفور.',
   'فلاشة USB 3.0 بجسم معدني قلاب، متاحة ١٦ / ٣٢ / ٦٤ جيجا. الحفر بالليزر على الجسم. بنقدر نحمّل عليها ملفاتك التعريفية قبل التسليم.',
   true,false,50,1,1,true,true,7,12,'معدن','6 × 2 سم',18,null,null,null,32,null,null,12,'الصين',false,150),

  ('powerbank-10000','tech','NC-TEC-02','باور بانك ١٠٠٠٠','Powerbank 10000mAh',
   'أغلى هدية بتُستخدم كل يوم.',
   'باور بانك ١٠٠٠٠ مللي أمبير بمدخل Type-C ومخرجين، شاشة نسبة شحن. الطباعة UV بألوان كاملة على الوش. بضمان سنة.',
   true,false,25,1,1,true,true,8,14,'ألومنيوم + ABS','14 × 6.8 × 1.5 سم',210,null,null,null,null,10000,null,12,'الصين',false,160),

  ('mousepad-fabric','tech','NC-TEC-03','ماوس باد قماش','Fabric mouse pad',
   'مساحة إعلانية بتقعد قدام العميل ٨ ساعات في اليوم.',
   'ماوس باد بسطح قماش وقاعدة مطاط مانعة للانزلاق، بحواف مخيطة. الطباعة سبليميشن على السطح بالكامل.',
   true,false,50,1,2,true,true,4,8,'قماش + مطاط','25 × 21 × 0.3 سم',95,null,null,null,null,null,null,null,'مصر',false,170),

  -- ---- شنط ----
  ('bag-canvas-tote','bags','NC-BAG-01','شنطة قماش توتال','Canvas tote bag',
   'بديل الكيس البلاستيك — وبتتشاف في الشارع.',
   'شنطة قماش كانفاس ١٢ أونصة بحمالات طويلة، ٣٨ × ٤٢ سم. طباعة سلك سكرين على وش واحد أو الاتنين. الاختيار المعتاد للمعارض والمبادرات البيئية.',
   true,false,50,2,2,true,true,5,9,'كانفاس 12 أونصة','38 × 42 سم',160,null,null,null,null,null,null,null,'مصر',true,180),

  ('backpack-laptop','bags','NC-BAG-02','شنطة ظهر لابتوب','Laptop backpack',
   'هدية الدفعة الجديدة أو المؤتمر الكبير.',
   'شنطة ظهر بجيب لابتوب ١٥.٦ بوصة مبطّن، قماش بوليستر مقاوم للماء، منفذ USB خارجي. التطريز أو الطباعة على الجيب الأمامي.',
   true,false,25,1,1,true,false,10,16,'بوليستر 600D','45 × 30 × 15 سم',680,null,null,null,null,null,null,6,'الصين',false,190),

  -- ---- ميداليات وساعات وبوكسات ----
  ('keychain-metal','keychains','NC-KEY-01','ميدالية معدن','Metal keychain',
   'أرخص حاجة بتفضل مع صاحبها سنين.',
   'ميدالية معدن مطلي بحلقة مفاتيح، وجهين قابلين للحفر. الحفر بالليزر أو الطباعة UV بألوان كاملة.',
   true,false,100,2,1,true,true,5,9,'معدن مطلي','4 × 3 سم',32,null,null,null,null,null,1,null,'الصين',false,200),

  ('keychain-name-gift','keychains','NC-KEY-02','ميدالية باسمك','Personalised keychain',
   'قطعة واحدة، محفور عليها الاسم اللي انت عايزه.',
   'ميدالية معدن بحفر ليزر للاسم أو التاريخ أو الإحداثيات. هدية سريعة وسعرها في المتناول، وبتتسلّم في علبة صغيرة.',
   false,true,1,2,2,false,true,2,4,'معدن مطلي','4 × 3 سم',32,null,null,null,null,null,1,null,'الصين',false,210),

  ('wallclock-round','clocks','NC-CLK-01','ساعة حائط دائرية','Round wall clock',
   'اللوجو في وش كل واحد داخل المقر.',
   'ساعة حائط قطر ٣٠ سم بحركة كوارتز صامتة وإطار بلاستيك. طباعة UV بألوان كاملة على القرص بالكامل.',
   true,false,25,1,2,true,true,7,12,'بلاستيك + زجاج','قطر 30 سم',520,null,null,null,null,null,null,12,'الصين',false,220),

  ('giftbox-ramadan','giftbox','NC-BOX-01','بوكس رمضان','Ramadan gift box',
   'مج وأجندة وقلم وتمر في علبة واحدة عليها اسم الشركة.',
   'بوكس مجمّع بيتظبط حسب طلبك: مج سيراميك + أجندة A5 + قلم معدن + علبة تمر، في علبة كرتون فاخرة بطباعة كاملة وشريطة. المحتويات قابلة للتغيير.',
   true,true,20,1,2,true,true,10,18,'كرتون مقوى','30 × 25 × 10 سم',1400,null,null,null,null,null,null,null,'مصر',false,230),

  -- ---- مطبوعات ----
  ('businesscards-500','printing','NC-PRN-01','كروت شخصية','Business cards',
   'أول حاجة بتتسلّم في إيد العميل.',
   'كروت شخصية ٣٥٠ جرام كوشيه بسلوفان مط أو لامع، طباعة وجهين بألوان كاملة. السعر بالعبوة (٥٠٠ كارت). متاح الفويل الذهبي والحفر البارز كإضافة.',
   true,false,1,2,3,true,true,3,5,'كوشيه 350 جرام','9 × 5.5 سم',null,null,350,null,null,null,500,null,'مصر',false,240)
) as v(slug, cat_slug, sku, name_ar, name_en, pitch, descr,
       corp, indiv, moq, max_pos, max_lines, logo, txt, lead_min, lead_max,
       material, dims, weight, capacity, gsm, pages, usb, mah, pack, warranty,
       origin, eco, sort)
join public.categories c on c.slug = v.cat_slug
on conflict (slug) do nothing;

-- ------------------------------------------------------ شرايح الأسعار ------
--
-- Non-increasing as min_qty rises — the trigger in 20260810100003 refuses
-- anything else, because a rung that goes UP with quantity is a typo that
-- silently overcharges.

insert into public.product_price_tiers (product_id, min_qty, unit_price)
select p.id, v.min_qty::int, v.unit_price::numeric
  from (values
    ('mug-ceramic-white',36,75),('mug-ceramic-white',100,65),('mug-ceramic-white',250,58),('mug-ceramic-white',500,52),('mug-ceramic-white',1000,47),
    ('mug-magic-color',24,135),('mug-magic-color',100,120),('mug-magic-color',250,108),('mug-magic-color',500,98),
    ('mug-travel-steel',25,295),('mug-travel-steel',100,270),('mug-travel-steel',250,248),('mug-travel-steel',500,229),
    ('mug-name-gift',1,190),('mug-name-gift',5,155),('mug-name-gift',12,125),('mug-name-gift',36,88),('mug-name-gift',100,72),
    ('bottle-steel-750',25,340),('bottle-steel-750',100,312),('bottle-steel-750',250,288),('bottle-steel-750',500,265),
    ('bottle-tritan-700',50,118),('bottle-tritan-700',100,105),('bottle-tritan-700',250,95),('bottle-tritan-700',500,86),
    ('pen-metal-classic',100,42),('pen-metal-classic',250,37),('pen-metal-classic',500,33),('pen-metal-classic',1000,29),
    ('pen-plastic-promo',250,9),('pen-plastic-promo',500,7.5),('pen-plastic-promo',1000,6.25),('pen-plastic-promo',5000,5),
    ('pen-set-gift',25,320),('pen-set-gift',100,290),('pen-set-gift',250,265),
    ('notebook-a5-pu',50,165),('notebook-a5-pu',100,148),('notebook-a5-pu',250,132),('notebook-a5-pu',500,119),
    ('notebook-spiral-a4',100,72),('notebook-spiral-a4',250,64),('notebook-spiral-a4',500,57),('notebook-spiral-a4',1000,51),
    ('tshirt-cotton-round',24,185),('tshirt-cotton-round',100,168),('tshirt-cotton-round',250,152),('tshirt-cotton-round',500,138),
    ('polo-pique',24,285),('polo-pique',100,262),('polo-pique',250,240),('polo-pique',500,222),
    ('cap-baseball',50,118),('cap-baseball',100,106),('cap-baseball',250,95),('cap-baseball',500,86),
    ('usb-metal-flip',50,205),('usb-metal-flip',100,188),('usb-metal-flip',250,172),('usb-metal-flip',500,158),
    ('powerbank-10000',25,485),('powerbank-10000',100,445),('powerbank-10000',250,412),('powerbank-10000',500,385),
    ('mousepad-fabric',50,68),('mousepad-fabric',100,60),('mousepad-fabric',250,53),('mousepad-fabric',500,47),
    ('bag-canvas-tote',50,95),('bag-canvas-tote',100,85),('bag-canvas-tote',250,76),('bag-canvas-tote',500,68),
    ('backpack-laptop',25,720),('backpack-laptop',100,665),('backpack-laptop',250,615),
    ('keychain-metal',100,34),('keychain-metal',250,29),('keychain-metal',500,25),('keychain-metal',1000,21),
    ('keychain-name-gift',1,85),('keychain-name-gift',5,68),('keychain-name-gift',12,54),('keychain-name-gift',50,36),
    ('wallclock-round',25,265),('wallclock-round',100,242),('wallclock-round',250,222),
    ('giftbox-ramadan',20,520),('giftbox-ramadan',50,478),('giftbox-ramadan',100,442),('giftbox-ramadan',250,408),
    ('businesscards-500',1,320),('businesscards-500',5,285),('businesscards-500',10,255),('businesscards-500',25,228)
  ) as v(slug, min_qty, unit_price)
  join public.products p on p.slug = v.slug
on conflict (product_id, min_qty) do nothing;

-- ------------------------------------------------ طرق الطباعة لكل منتج ------

insert into public.product_print_methods
  (product_id, method_code, setup_fee, setup_fee_per_color, setup_fee_waived_over_qty,
   unit_addon, addon_per_color, max_colors, method_min_qty, is_default)
select p.id, v.method_code, v.setup::numeric, v.per_color::boolean, v.waived::int,
       v.addon::numeric, v.addon_color::numeric, v.max_colors::int, v.min_qty::int, v.is_def::boolean
  from (values
    ('mug-ceramic-white','sublimation',0,false,null,0,0,null,null,true),
    ('mug-ceramic-white','screen',150,true,500,0,2,3,36,false),
    ('mug-magic-color','sublimation',0,false,null,0,0,null,null,true),
    ('mug-travel-steel','laser',0,false,null,12,0,null,null,true),
    ('mug-travel-steel','uv',100,false,250,8,0,null,null,false),
    ('mug-name-gift','sublimation',0,false,null,0,0,null,null,true),
    ('bottle-steel-750','laser',0,false,null,15,0,null,null,true),
    ('bottle-steel-750','uv',100,false,250,10,0,null,null,false),
    ('bottle-tritan-700','screen',150,true,500,0,1.5,3,50,true),
    ('bottle-tritan-700','uv',100,false,250,7,0,null,null,false),
    ('pen-metal-classic','laser',0,false,null,4,0,null,null,true),
    ('pen-metal-classic','pad',120,true,1000,0,1,2,100,false),
    ('pen-plastic-promo','pad',120,true,1000,0,0.75,2,250,true),
    ('pen-set-gift','laser',0,false,null,18,0,null,null,true),
    ('notebook-a5-pu','emboss',350,false,500,0,0,null,50,true),
    ('notebook-a5-pu','foil',200,false,500,6,0,null,50,false),
    ('notebook-a5-pu','screen',150,true,500,0,2,2,50,false),
    ('notebook-spiral-a4','digital',0,false,null,0,0,null,null,true),
    ('tshirt-cotton-round','dtf',0,false,null,22,0,null,null,true),
    ('tshirt-cotton-round','embroidery',250,false,250,18,3,8,24,false),
    ('tshirt-cotton-round','screen',150,true,500,0,3,4,50,false),
    ('polo-pique','embroidery',250,false,250,20,3,8,24,true),
    ('polo-pique','dtf',0,false,null,22,0,null,null,false),
    ('cap-baseball','embroidery',250,false,250,16,3,8,50,true),
    ('usb-metal-flip','laser',0,false,null,6,0,null,null,true),
    ('usb-metal-flip','uv',100,false,250,9,0,null,null,false),
    ('powerbank-10000','uv',100,false,250,14,0,null,null,true),
    ('powerbank-10000','laser',0,false,null,10,0,null,null,false),
    ('mousepad-fabric','sublimation',0,false,null,0,0,null,null,true),
    ('bag-canvas-tote','screen',150,true,500,0,2.5,4,50,true),
    ('bag-canvas-tote','dtf',0,false,null,20,0,null,null,false),
    ('backpack-laptop','embroidery',250,false,250,24,3,8,25,true),
    ('backpack-laptop','screen',150,true,500,0,3,3,50,false),
    ('keychain-metal','laser',0,false,null,3,0,null,null,true),
    ('keychain-metal','uv',100,false,500,5,0,null,null,false),
    ('keychain-name-gift','laser',0,false,null,3,0,null,null,true),
    ('wallclock-round','uv',100,false,250,18,0,null,null,true),
    ('giftbox-ramadan','digital',0,false,null,0,0,null,null,true),
    ('giftbox-ramadan','foil',200,false,250,12,0,null,null,false),
    ('businesscards-500','digital',0,false,null,0,0,null,null,true),
    ('businesscards-500','foil',200,false,25,45,0,null,null,false),
    ('businesscards-500','emboss',350,false,25,55,0,null,null,false)
  ) as v(slug, method_code, setup, per_color, waived, addon, addon_color, max_colors, min_qty, is_def)
  join public.products p on p.slug = v.slug
on conflict (product_id, method_code) do nothing;

-- ----------------------------------------------- أماكن الطباعة لكل منتج ----
--
-- preview_* are PERCENTAGES of the cover image. They are what makes the live
-- preview data-driven: four numbers per position instead of a component per
-- product. Left null here for products whose cover photo does not exist yet —
-- the preview simply does not render, which is the correct degradation.

insert into public.print_positions
  (product_id, code, name_ar, area_w_mm, area_h_mm,
   preview_x, preview_y, preview_w, preview_h, is_default, sort_order)
select p.id, v.code, v.name_ar, v.w::numeric, v.h::numeric,
       v.px::numeric, v.py::numeric, v.pw::numeric, v.ph::numeric, v.is_def::boolean, v.sort::int
  from (values
    ('mug-ceramic-white','front','الوش',90,80,34,32,32,30,true,10),
    ('mug-ceramic-white','back','الضهر',90,80,null,null,null,null,false,20),
    ('mug-magic-color','front','الوش',90,80,34,32,32,30,true,10),
    ('mug-travel-steel','body','جسم الترمس',60,40,36,38,28,18,true,10),
    ('mug-name-gift','front','الوش',90,80,34,32,32,30,true,10),
    ('mug-name-gift','back','الضهر',90,80,null,null,null,null,false,20),
    ('bottle-steel-750','body','جسم الزجاجة',55,120,40,32,20,34,true,10),
    ('bottle-tritan-700','body','جسم الزجاجة',60,100,40,32,20,30,true,10),
    ('pen-metal-classic','barrel','جسم القلم',45,6,30,46,40,6,true,10),
    ('pen-plastic-promo','barrel','جسم القلم',50,7,30,46,40,6,true,10),
    ('pen-plastic-promo','clip','الكليب',25,4,null,null,null,null,false,20),
    ('pen-set-gift','barrel','جسم القلم',45,6,30,46,40,6,true,10),
    ('pen-set-gift','box','بلاكة العلبة',40,15,null,null,null,null,false,20),
    ('notebook-a5-pu','cover','الغلاف',80,40,32,34,36,22,true,10),
    ('notebook-spiral-a4','cover','الغلاف الكامل',297,210,12,10,76,80,true,10),
    ('tshirt-cotton-round','chest_left','صدر شمال',90,90,58,30,16,16,true,10),
    ('tshirt-cotton-round','chest_full','الصدر بالكامل',280,300,30,28,40,40,false,20),
    ('tshirt-cotton-round','back','الضهر',300,350,null,null,null,null,false,30),
    ('polo-pique','chest_left','صدر شمال',80,80,58,30,15,15,true,10),
    ('polo-pique','sleeve','الكم',60,60,null,null,null,null,false,20),
    ('cap-baseball','front','الوش',110,50,34,38,32,16,true,10),
    ('cap-baseball','side','الجنب',60,30,null,null,null,null,false,20),
    ('usb-metal-flip','body','جسم الفلاشة',35,10,32,44,36,10,true,10),
    ('powerbank-10000','front','الوش',90,50,30,32,40,26,true,10),
    ('mousepad-fabric','full','السطح بالكامل',250,210,8,10,84,80,true,10),
    ('bag-canvas-tote','front','الوش',280,300,28,30,44,40,true,10),
    ('bag-canvas-tote','back','الضهر',280,300,null,null,null,null,false,20),
    ('backpack-laptop','front_pocket','الجيب الأمامي',120,80,36,42,28,18,true,10),
    ('keychain-metal','side_a','الوجه الأول',30,20,36,40,28,20,true,10),
    ('keychain-metal','side_b','الوجه التاني',30,20,null,null,null,null,false,20),
    ('keychain-name-gift','side_a','الوجه الأول',30,20,36,40,28,20,true,10),
    ('keychain-name-gift','side_b','الوجه التاني',30,20,null,null,null,null,false,20),
    ('wallclock-round','dial','قرص الساعة',260,260,18,18,64,64,true,10),
    ('giftbox-ramadan','lid','غطا العلبة',250,200,20,22,60,48,true,10),
    ('businesscards-500','front','الوش',90,55,10,14,80,72,true,10),
    ('businesscards-500','back','الضهر',90,55,null,null,null,null,false,20)
  ) as v(slug, code, name_ar, w, h, px, py, pw, ph, is_def, sort)
  join public.products p on p.slug = v.slug
on conflict (product_id, code) do nothing;

-- A worked example of the override table. Everywhere else it stays empty,
-- which by the documented convention means "every method the product supports
-- works here". On the travel mug the handle is the exception: pad printing
-- reaches it, laser does not.
insert into public.position_print_methods (position_id, method_code, area_w_mm, area_h_mm, max_colors)
select pos.id, 'uv', 40, 25, null
  from public.print_positions pos
  join public.products p on p.id = pos.product_id
 where p.slug = 'mug-travel-steel' and pos.code = 'body'
on conflict do nothing;

-- ------------------------------------------------------------- خيارات ------

insert into public.product_option_groups (product_id, code, label_ar, is_required, sort_order)
select p.id, v.code, v.label_ar, v.req::boolean, v.sort::int
  from (values
    ('mug-ceramic-white','color','لون الداخل والودن',false,10),
    ('mug-name-gift','color','لون الداخل والودن',false,10),
    ('bottle-steel-750','color','لون الزجاجة',true,10),
    ('pen-plastic-promo','color','لون جسم القلم',true,10),
    ('tshirt-cotton-round','color','اللون',true,10),
    ('tshirt-cotton-round','size','المقاس',true,20),
    ('polo-pique','color','اللون',true,10),
    ('polo-pique','size','المقاس',true,20),
    ('cap-baseball','color','اللون',true,10),
    ('usb-metal-flip','capacity','السعة',true,10),
    ('notebook-a5-pu','color','لون الغلاف',true,10),
    ('bag-canvas-tote','color','لون القماش',true,10),
    ('businesscards-500','finish','التشطيب',true,10)
  ) as v(slug, code, label_ar, req, sort)
  join public.products p on p.slug = v.slug
on conflict (product_id, code) do nothing;

insert into public.product_option_items (group_id, value, label_ar, hex, price_delta, is_available, sort_order)
select g.id, v.value, v.label_ar, v.hex, v.delta::numeric, v.avail::boolean, v.sort::int
  from (values
    ('mug-ceramic-white','color','white','أبيض بالكامل','#FFFFFF',0,true,10),
    ('mug-ceramic-white','color','black','داخل أسود','#111111',8,true,20),
    ('mug-ceramic-white','color','red','داخل أحمر','#C62828',8,true,30),
    ('mug-ceramic-white','color','blue','داخل أزرق','#1565C0',8,false,40),
    ('mug-name-gift','color','white','أبيض بالكامل','#FFFFFF',0,true,10),
    ('mug-name-gift','color','black','داخل أسود','#111111',10,true,20),
    ('mug-name-gift','color','pink','داخل بمبي','#EC407A',10,true,30),
    ('bottle-steel-750','color','silver','فضي','#C0C4CC',0,true,10),
    ('bottle-steel-750','color','black','أسود مط','#1A1A1A',12,true,20),
    ('bottle-steel-750','color','navy','كحلي','#1B2A4A',12,true,30),
    ('pen-plastic-promo','color','white','أبيض','#FFFFFF',0,true,10),
    ('pen-plastic-promo','color','blue','أزرق','#1565C0',0,true,20),
    ('pen-plastic-promo','color','red','أحمر','#C62828',0,true,30),
    ('pen-plastic-promo','color','green','أخضر','#2E7D32',0,true,40),
    ('tshirt-cotton-round','color','white','أبيض','#FFFFFF',0,true,10),
    ('tshirt-cotton-round','color','black','أسود','#111111',0,true,20),
    ('tshirt-cotton-round','color','navy','كحلي','#1B2A4A',0,true,30),
    ('tshirt-cotton-round','color','grey','رمادي','#9E9E9E',0,true,40),
    ('tshirt-cotton-round','size','s','S',null,0,true,10),
    ('tshirt-cotton-round','size','m','M',null,0,true,20),
    ('tshirt-cotton-round','size','l','L',null,0,true,30),
    ('tshirt-cotton-round','size','xl','XL',null,0,true,40),
    ('tshirt-cotton-round','size','xxl','2XL',null,12,true,50),
    ('tshirt-cotton-round','size','xxxl','3XL',null,20,true,60),
    ('polo-pique','color','white','أبيض','#FFFFFF',0,true,10),
    ('polo-pique','color','navy','كحلي','#1B2A4A',0,true,20),
    ('polo-pique','color','black','أسود','#111111',0,true,30),
    ('polo-pique','size','s','S',null,0,true,10),
    ('polo-pique','size','m','M',null,0,true,20),
    ('polo-pique','size','l','L',null,0,true,30),
    ('polo-pique','size','xl','XL',null,0,true,40),
    ('polo-pique','size','xxl','2XL',null,15,true,50),
    ('cap-baseball','color','black','أسود','#111111',0,true,10),
    ('cap-baseball','color','navy','كحلي','#1B2A4A',0,true,20),
    ('cap-baseball','color','white','أبيض','#FFFFFF',0,true,30),
    ('usb-metal-flip','capacity','16','١٦ جيجا',null,0,true,10),
    ('usb-metal-flip','capacity','32','٣٢ جيجا',null,35,true,20),
    ('usb-metal-flip','capacity','64','٦٤ جيجا',null,85,true,30),
    ('notebook-a5-pu','color','black','أسود','#111111',0,true,10),
    ('notebook-a5-pu','color','navy','كحلي','#1B2A4A',0,true,20),
    ('notebook-a5-pu','color','brown','بني','#6D4C41',0,true,30),
    ('bag-canvas-tote','color','natural','بيچ طبيعي','#D9CDB4',0,true,10),
    ('bag-canvas-tote','color','black','أسود','#111111',6,true,20),
    ('businesscards-500','finish','matte','سلوفان مط',null,0,true,10),
    ('businesscards-500','finish','gloss','سلوفان لامع',null,0,true,20),
    ('businesscards-500','finish','softtouch','سوفت تاتش',null,45,true,30)
  ) as v(slug, group_code, value, label_ar, hex, delta, avail, sort)
  join public.products p on p.slug = v.slug
  join public.product_option_groups g on g.product_id = p.id and g.code = v.group_code
on conflict (group_id, value) do nothing;

-- ------------------------------------------------- ربط المنتج بالمناسبة ----

insert into public.product_occasions (product_id, occasion_id, is_primary)
select p.id, o.id, v.prim::boolean
  from (values
    ('giftbox-ramadan','ramadan',true),
    ('mug-ceramic-white','conference',true),
    ('notebook-a5-pu','new-year',true),
    ('notebook-spiral-a4','conference',true),
    ('bag-canvas-tote','conference',false),
    ('pen-set-gift','opening',true),
    ('mug-name-gift','birthday',true),
    ('mug-name-gift','love',false),
    ('keychain-name-gift','love',true),
    ('keychain-name-gift','graduation',false),
    ('tshirt-cotton-round','graduation',true),
    ('wallclock-round','opening',false),
    ('mug-magic-color','mothers-day',true)
  ) as v(slug, occ_slug, prim)
  join public.products  p on p.slug = v.slug
  join public.occasions o on o.slug = v.occ_slug
on conflict do nothing;

-- ------------------------------------------------------------- النشر ------
--
-- Last, and only now. Every product below has a tier at or below its MOQ, at
-- least one print method and at least one position — the three things
-- pricing_complete() insists on. Publishing before this point raises
-- PRICING_INCOMPLETE, which is the gate working, not the seed failing.

update public.products set is_published = true where is_published = false;

update public.products set is_featured = true
 where slug in ('mug-ceramic-white','notebook-a5-pu','tshirt-cotton-round',
                'usb-metal-flip','bag-canvas-tote','giftbox-ramadan');
