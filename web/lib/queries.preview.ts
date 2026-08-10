// PREVIEW DATA LAYER — never reached in production, and never present there.
//
// `npm run preview:on` copies this file over lib/queries.ts on the developer's
// machine; `npm run preview:off` puts the real one back. A bundler alias was
// tried first and silently lost to the tsconfig-paths plugin — see
// tools/preview/toggle.mjs for the full reasoning, including why a
// `process.env.PREVIEW` branch inside queries.ts was rejected.
//
// Everything below reads tools/preview/dump.mjs's dump of the actual migrations
// and seed, so the pages render real catalogue data with no Supabase project in
// existence yet.
//
// Regenerate after any change to supabase/:  npm run preview:dump

import previewData from '../preview-data.json';
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

export type Audience = 'corporate' | 'individual';
export type SortKey = 'featured' | 'cheap' | 'expensive' | 'newest' | 'name';

export interface CatalogFilters {
  category?: string;
  occasion?: string;
  audience?: Audience;
  method?: string;
  q?: string;
  sort?: SortKey;
  limit?: number;
}

interface PreviewProduct extends ProductCardRow {
  category_slug: string;
  occasion_slugs: string[];
  method_codes: string[];
  search_key: string;
}

const data = previewData as unknown as {
  settings: SiteSettings | null;
  categories: Category[];
  occasions: Occasion[];
  methods: PrintMethod[];
  products: PreviewProduct[];
  details: Record<string, ProductDetailRow>;
  specsByCategory: Record<string, SpecDef[]>;
  books: Record<string, PriceBook>;
};

export async function getSiteSettings(): Promise<SiteSettings | null> {
  return data.settings;
}

export async function getCategories(): Promise<Category[]> {
  return data.categories;
}

export async function getCategoryBySlug(slug: string): Promise<Category | null> {
  return data.categories.find((c) => c.slug === slug) ?? null;
}

export async function getOccasions(): Promise<Occasion[]> {
  return data.occasions;
}

export async function getOccasionBySlug(slug: string): Promise<Occasion | null> {
  return data.occasions.find((o) => o.slug === slug) ?? null;
}

export async function getPrintMethods(): Promise<PrintMethod[]> {
  return data.methods;
}

export async function getSpecsForCategory(categoryId: string): Promise<SpecDef[]> {
  return data.specsByCategory[categoryId] ?? [];
}

export async function listProducts(f: CatalogFilters = {}): Promise<ProductCardRow[]> {
  let out = data.products.slice();

  if (f.category) out = out.filter((p) => p.category_slug === f.category);
  if (f.occasion) out = out.filter((p) => p.occasion_slugs.includes(f.occasion as string));
  if (f.method) out = out.filter((p) => p.method_codes.includes(f.method as string));
  if (f.audience === 'corporate') out = out.filter((p) => p.for_corporate);
  if (f.audience === 'individual') out = out.filter((p) => p.for_individual);

  const term = f.q?.trim();
  if (term) {
    const folded = foldArabic(term);
    out = out.filter((p) => (p.search_key ?? '').includes(folded));
  }

  const price = (p: ProductCardRow) => Number(p.price_at_moq ?? Infinity);
  switch (f.sort) {
    case 'cheap':
      out.sort((a, b) => price(a) - price(b));
      break;
    case 'expensive':
      out.sort((a, b) => price(b) - price(a));
      break;
    case 'newest':
      out.sort((a, b) => (a.created_at < b.created_at ? 1 : -1));
      break;
    case 'name':
      out.sort((a, b) => a.name_ar.localeCompare(b.name_ar, 'ar'));
      break;
    default:
      out.sort(
        (a, b) => Number(b.is_featured) - Number(a.is_featured) || a.sort_order - b.sort_order
      );
  }

  return f.limit ? out.slice(0, f.limit) : out;
}

export async function getFeaturedProducts(limit = 8): Promise<ProductCardRow[]> {
  return data.products.filter((p) => p.is_featured).slice(0, limit);
}

export async function getProductBySlug(slug: string): Promise<ProductDetailRow | null> {
  return data.details[slug] ?? null;
}

export async function getPriceBook(productId: string): Promise<PriceBook | null> {
  const slug = data.products.find((p) => p.id === productId)?.slug;
  return slug ? (data.books[slug] ?? null) : null;
}

export async function resolveSlugAlias(_oldSlug: string): Promise<string | null> {
  // The dump carries no aliases: they only matter once a slug has been renamed
  // on a live site. The parameter stays so this module's signatures cannot
  // drift from queries.ts — the build is what catches that, and it just did.
  return null;
}

export async function getRelatedProducts(
  product: ProductCardRow,
  limit = 4
): Promise<ProductCardRow[]> {
  const sameCat = data.products.filter(
    (p) => p.category_id === product.category_id && p.id !== product.id
  );
  if (sameCat.length >= limit) return sameCat.slice(0, limit);
  const seen = new Set([product.id, ...sameCat.map((p) => p.id)]);
  const topUp = data.products.filter(
    (p) =>
      !seen.has(p.id) && (product.for_individual ? p.for_individual : p.for_corporate)
  );
  return [...sameCat, ...topUp].slice(0, limit);
}

export async function getAllRoutes(): Promise<{
  products: { slug: string; updated_at: string }[];
  categories: { slug: string }[];
  occasions: { slug: string }[];
}> {
  return {
    products: data.products.map((p) => ({ slug: p.slug, updated_at: p.created_at })),
    categories: data.categories.map((c) => ({ slug: c.slug })),
    occasions: data.occasions.map((o) => ({ slug: o.slug })),
  };
}
