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
