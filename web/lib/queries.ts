import { supabase } from './supabase';
import { isConfigured } from './env';
import { foldArabic } from './arabic';
import type {
  Category,
  Occasion,
  PrintMethod,
  ProductCardRow,
  ProductDetailRow,
  SiteSettings,
  SpecDef,
} from './types';
import type { PriceBook } from './pricing.types';

// Every read the shop window needs. All anonymous, all filtered by RLS on the
// server side — nothing here decides what a visitor may see, it only decides
// what to ask for.

// Every function below opens with `if (!isConfigured) return <empty>`.
//
// `next build` renders every page, including on a machine that has never seen
// the Supabase keys — a build that dies with "supabase is not configured" is a
// build gate nobody can run. The visitor never sees these empties: the layout
// renders SetupRequired instead of the page when isConfigured is false, so an
// empty array here can never be mistaken for an empty catalogue.

const CARD_COLUMNS = `
  id, slug, name_ar, short_pitch_ar, cover_url, moq,
  price_at_moq, price_from, for_corporate, for_individual,
  is_available, is_featured, category_id, sort_order, created_at,
  material_ar, dimensions_ar, weight_g, capacity_ml, paper_gsm, page_count,
  usb_capacity_gb, battery_mah, pack_size, warranty_months, origin_ar, is_eco
`;

/**
 * Contact details, VAT rate, currency. Decoration, not content — so a failure
 * here returns null rather than taking a page down. Every caller already
 * handles null, because the row can also be genuinely empty on a fresh
 * install. The catalogue queries below deliberately do NOT swallow errors: an
 * empty shop must be loud.
 */
export async function getSiteSettings(): Promise<SiteSettings | null> {
  if (!isConfigured) return null;
  try {
    const { data } = await supabase().from('site_settings').select('*').maybeSingle();
    return (data as SiteSettings) ?? null;
  } catch {
    return null;
  }
}

export async function getCategories(): Promise<Category[]> {
  if (!isConfigured) return [];
  const { data } = await supabase()
    .from('categories')
    .select('*')
    .eq('is_active', true)
    .order('sort_order');
  return (data as Category[]) ?? [];
}

export async function getCategoryBySlug(slug: string): Promise<Category | null> {
  if (!isConfigured) return null;
  const { data } = await supabase()
    .from('categories')
    .select('*')
    .eq('slug', slug)
    .maybeSingle();
  return (data as Category) ?? null;
}

export async function getOccasions(): Promise<Occasion[]> {
  if (!isConfigured) return [];
  const { data } = await supabase()
    .from('occasions')
    .select('*')
    .eq('is_active', true)
    .order('sort_order');
  return (data as Occasion[]) ?? [];
}

export async function getOccasionBySlug(slug: string): Promise<Occasion | null> {
  if (!isConfigured) return null;
  const { data } = await supabase()
    .from('occasions')
    .select('*')
    .eq('slug', slug)
    .maybeSingle();
  return (data as Occasion) ?? null;
}

export async function getPrintMethods(): Promise<PrintMethod[]> {
  if (!isConfigured) return [];
  const { data } = await supabase()
    .from('print_methods')
    .select('*')
    .eq('is_active', true)
    .order('sort_order');
  return (data as PrintMethod[]) ?? [];
}

/**
 * The spec catalogue for one category, honouring the "no rows = every category"
 * convention. Resolved in SQL by specs_for_category() so the site, the admin
 * form and the harness all get the same answer from the same place.
 */
export async function getSpecsForCategory(categoryId: string): Promise<SpecDef[]> {
  if (!isConfigured) return [];
  const { data } = await supabase().rpc('specs_for_category', { p_category: categoryId });
  return (data as SpecDef[]) ?? [];
}

export type Audience = 'corporate' | 'individual';
export type SortKey = 'featured' | 'cheap' | 'expensive' | 'newest' | 'name';

export interface CatalogFilters {
  category?: string; // slug
  occasion?: string; // slug
  audience?: Audience;
  method?: string; // print method code
  q?: string;
  sort?: SortKey;
  limit?: number;
}

/**
 * The catalogue query.
 *
 * Sorting and filtering happen in SQL, never in JavaScript over a fetched
 * array — the day the catalogue passes a thousand products, a client-side sort
 * is a thousand rows over Egyptian mobile data to show twenty.
 *
 * Note the sort key: `price_at_moq`, never `price_from`. Ordering by the
 * thousand-piece price shows a customer buying fifty a ladder they cannot
 * reach, which is the MOQ trap dressed up as a feature.
 */
export async function listProducts(f: CatalogFilters = {}): Promise<ProductCardRow[]> {
  if (!isConfigured) return [];
  // `!inner` turns an embedded table into a join, so filtering on it filters
  // the products themselves rather than just trimming the embedded array.
  const joins = [
    f.occasion ? 'product_occasions!inner(occasion_id, occasions!inner(slug))' : '',
    f.method ? 'product_print_methods!inner(method_code)' : '',
    f.category ? 'categories!inner(slug)' : '',
  ].filter(Boolean);

  let query = supabase()
    .from('products')
    .select([CARD_COLUMNS, ...joins].join(', '))
    .eq('is_published', true);

  if (f.category) query = query.eq('categories.slug', f.category);
  if (f.occasion) query = query.eq('product_occasions.occasions.slug', f.occasion);
  if (f.method) query = query.eq('product_print_methods.method_code', f.method);
  if (f.audience === 'corporate') query = query.eq('for_corporate', true);
  if (f.audience === 'individual') query = query.eq('for_individual', true);

  // Fold the search term the same way the stored column was folded, or the box
  // returns nothing for the words people actually type.
  const term = f.q?.trim();
  if (term) query = query.like('search_key', `%${foldArabic(term)}%`);

  switch (f.sort) {
    case 'cheap':
      query = query.order('price_at_moq', { ascending: true, nullsFirst: false });
      break;
    case 'expensive':
      query = query.order('price_at_moq', { ascending: false, nullsFirst: false });
      break;
    case 'newest':
      query = query.order('created_at', { ascending: false });
      break;
    case 'name':
      query = query.order('name_ar', { ascending: true });
      break;
    default:
      query = query.order('is_featured', { ascending: false }).order('sort_order');
  }

  if (f.limit) query = query.limit(f.limit);

  const { data, error } = await query;
  if (error) throw error;
  // The `!inner` joins add embedded keys the card does not use; the cast is
  // narrowing to what the card reads, not inventing fields.
  return (data as unknown as ProductCardRow[]) ?? [];
}

export async function getFeaturedProducts(limit = 8): Promise<ProductCardRow[]> {
  if (!isConfigured) return [];
  const { data } = await supabase()
    .from('products')
    .select(CARD_COLUMNS)
    .eq('is_published', true)
    .eq('is_featured', true)
    .order('sort_order')
    .limit(limit);
  return (data as ProductCardRow[]) ?? [];
}

/**
 * One product, shaped for RENDERING: gallery, spec sheet, breadcrumbs.
 *
 * Its sibling getPriceBook() shapes the same product for ARITHMETIC. Two reads
 * rather than one because the two jobs want different things — the page needs
 * images and prose, the configurator needs resolved ceilings and fees — and
 * merging them would give both a payload full of fields they ignore.
 */
export async function getProductBySlug(slug: string): Promise<ProductDetailRow | null> {
  if (!isConfigured) return null;
  const { data, error } = await supabase()
    .from('products')
    .select(`
      *,
      categories ( id, slug, name_ar ),
      product_price_tiers ( min_qty, unit_price ),
      product_print_methods (
        method_code, setup_fee, setup_fee_per_color, setup_fee_waived_over_qty,
        unit_addon, addon_per_color, max_colors, method_min_qty, is_default,
        print_methods ( code, name_ar, name_en, blurb_ar, color_model,
                        needs_vector, default_setup_fee, default_max_colors,
                        sort_order, is_active )
      ),
      print_positions (
        id, code, name_ar, name_en, area_w_mm, area_h_mm,
        preview_x, preview_y, preview_w, preview_h, preview_rotate,
        is_default, sort_order
      ),
      product_option_groups (
        id, code, label_ar, is_required, sort_order,
        product_option_items ( id, value, label_ar, hex, price_delta,
                               is_available, image_url, sort_order )
      ),
      product_images ( id, url, alt_ar, option_item_id, sort_order )
    `)
    .eq('slug', slug)
    .maybeSingle();

  if (error) throw error;
  if (!data) return null;

  const p = data as unknown as ProductDetailRow;
  // Order the children here rather than in the query: PostgREST cannot order
  // an embedded table and a nested one at the same time, and getting this
  // wrong shows up as a price ladder listed backwards.
  p.product_price_tiers.sort((a, b) => a.min_qty - b.min_qty);
  p.print_positions.sort((a, b) => a.sort_order - b.sort_order);
  p.product_images.sort((a, b) => a.sort_order - b.sort_order);
  p.product_option_groups.sort((a, b) => a.sort_order - b.sort_order);
  for (const g of p.product_option_groups) {
    g.product_option_items.sort((a, b) => a.sort_order - b.sort_order);
  }
  p.product_print_methods.sort(
    (a, b) => (a.print_methods?.sort_order ?? 0) - (b.print_methods?.sort_order ?? 0)
  );
  return p;
}

/**
 * The price book: everything the configurator needs to compute a total without
 * another request.
 *
 * This IS a second read of the same product, on purpose. getProductBySlug()
 * shapes the row for rendering; quote_product() shapes it for arithmetic, with
 * the position/method convention and the colour ceilings already resolved in
 * SQL. Giving the browser the raw tables and asking it to resolve those rules
 * itself is how the two would drift.
 */
export async function getPriceBook(productId: string): Promise<PriceBook | null> {
  if (!isConfigured) return null;
  const { data, error } = await supabase().rpc('quote_product', { p_product: productId });
  if (error) throw error;
  return (data as PriceBook) ?? null;
}

/**
 * A slug that used to belong to a product. One table and a 301 is the entire
 * insurance policy for a link somebody shared on WhatsApp two years ago.
 */
export async function resolveSlugAlias(oldSlug: string): Promise<string | null> {
  if (!isConfigured) return null;
  const { data } = await supabase()
    .from('product_slug_aliases')
    .select('products ( slug )')
    .eq('old_slug', oldSlug)
    .maybeSingle();
  const row = data as { products?: { slug: string } | null } | null;
  return row?.products?.slug ?? null;
}

/** Same category first, topped up from the same audience. Never empty-handed. */
export async function getRelatedProducts(
  product: ProductCardRow,
  limit = 4
): Promise<ProductCardRow[]> {
  if (!isConfigured) return [];
  const { data: sameCat } = await supabase()
    .from('products')
    .select(CARD_COLUMNS)
    .eq('is_published', true)
    .eq('category_id', product.category_id)
    .neq('id', product.id)
    .order('sort_order')
    .limit(limit);

  const out = (sameCat as ProductCardRow[]) ?? [];
  if (out.length >= limit) return out;

  const { data: topUp } = await supabase()
    .from('products')
    .select(CARD_COLUMNS)
    .eq('is_published', true)
    .eq(product.for_individual ? 'for_individual' : 'for_corporate', true)
    .neq('id', product.id)
    .not('id', 'in', `(${[product.id, ...out.map((p) => p.id)].join(',')})`)
    .order('is_featured', { ascending: false })
    .limit(limit - out.length);

  return [...out, ...((topUp as ProductCardRow[]) ?? [])];
}

/** Everything the sitemap needs, in three cheap queries. */
export async function getAllRoutes(): Promise<{
  products: { slug: string; updated_at: string }[];
  categories: { slug: string }[];
  occasions: { slug: string }[];
}> {
  if (!isConfigured) return { products: [], categories: [], occasions: [] };
  const client = supabase();
  const [products, categories, occasions] = await Promise.all([
    client.from('products').select('slug, updated_at').eq('is_published', true),
    client.from('categories').select('slug').eq('is_active', true),
    client.from('occasions').select('slug').eq('is_active', true),
  ]);
  return {
    products: (products.data as { slug: string; updated_at: string }[]) ?? [],
    categories: (categories.data as { slug: string }[]) ?? [],
    occasions: (occasions.data as { slug: string }[]) ?? [],
  };
}
