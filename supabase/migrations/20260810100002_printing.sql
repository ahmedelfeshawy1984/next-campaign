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
