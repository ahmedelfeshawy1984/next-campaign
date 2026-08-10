import Link from 'next/link';
import { S } from '@/lib/strings';
import {
  listProducts,
  getCategories,
  getOccasions,
  getPrintMethods,
  getSiteSettings,
  getSpecsForCategory,
  type Audience,
  type SortKey,
} from '@/lib/queries';
import { filterUrl, param, type SearchParams } from '@/lib/urls';
import ProductGrid from './ProductGrid';
import { formatQty } from '@/lib/money';

const SORTS: { key: SortKey; label: string }[] = [
  { key: 'featured', label: S.catalog.sortFeatured },
  { key: 'cheap', label: S.catalog.sortCheap },
  { key: 'expensive', label: S.catalog.sortExpensive },
  { key: 'newest', label: S.catalog.sortNewest },
  { key: 'name', label: S.catalog.sortName },
];

/**
 * The catalogue, shared by /c/[slug], /o/[slug], /corporate and /gifts.
 *
 * `locked` names the axis this page already fixes — a category page must not
 * show a category filter that navigates away from itself. Everything else stays
 * filterable, and every control is a link, not a form.
 */
export default async function CatalogView({
  basePath,
  searchParams,
  fixed = {},
  locked = [],
}: {
  basePath: string;
  searchParams: SearchParams;
  fixed?: { category?: string; occasion?: string; audience?: Audience };
  locked?: ('category' | 'occasion' | 'audience')[];
}) {
  const sort = (param(searchParams, 'sort') as SortKey | undefined) ?? 'featured';
  const q = param(searchParams, 'q');
  const method = param(searchParams, 'method');

  const category = fixed.category ?? param(searchParams, 'category');
  const occasion = fixed.occasion ?? param(searchParams, 'occasion');
  const audience =
    fixed.audience ?? (param(searchParams, 'audience') as Audience | undefined);

  const [products, categories, occasions, methods, settings] = await Promise.all([
    listProducts({ category, occasion, audience, method, q, sort }),
    getCategories(),
    getOccasions(),
    getPrintMethods(),
    getSiteSettings(),
  ]);

  const currency = settings?.currency ?? S.common.currency;

  // Card specs are per-category. On a mixed listing there is no single answer,
  // so the cards fall back to no spec line rather than showing paper weight on
  // a powerbank.
  const activeCategory = category ? categories.find((c) => c.slug === category) : undefined;
  const cardSpecs = activeCategory
    ? (await getSpecsForCategory(activeCategory.id)).filter((d) => d.show_in_card)
    : [];

  const url = (patch: Record<string, string | undefined>) =>
    filterUrl(basePath, searchParams, patch);

  const hasFilters = !!(q || method ||
    (!locked.includes('category') && category) ||
    (!locked.includes('occasion') && occasion) ||
    (!locked.includes('audience') && audience));

  return (
    <div className="wrap catalog">
      <aside className="filters" aria-label="فلاتر">
        <form className="search" action={basePath}>
          {/* Hidden inputs carry the other filters through a search — otherwise
              typing in the box silently clears the category you picked. */}
          {Object.entries(searchParams).map(([k, v]) => {
            const s = Array.isArray(v) ? v[0] : v;
            return k === 'q' || !s ? null : <input key={k} type="hidden" name={k} value={s} />;
          })}
          <input
            type="search"
            name="q"
            defaultValue={q ?? ''}
            placeholder={S.catalog.searchPlaceholder}
            aria-label={S.nav.search}
          />
          <button className="btn btn--brand btn--sm" type="submit">
            بحث
          </button>
        </form>

        {hasFilters ? (
          <div style={{ marginBlockStart: 14 }}>
            <Link
              className="chip chip--muted"
              href={filterUrl(basePath, {}, {})}
            >
              ✕ {S.catalog.clearFilters}
            </Link>
          </div>
        ) : null}

        {!locked.includes('audience') ? (
          <div className="filters__group">
            <div className="filters__label">{S.catalog.filterAudience}</div>
            <div className="filters__list">
              <Link href={url({ audience: undefined })} aria-current={!audience}>
                {S.catalog.all}
              </Link>
              <Link
                href={url({ audience: 'corporate' })}
                aria-current={audience === 'corporate'}
              >
                {S.catalog.audienceCorporate}
              </Link>
              <Link
                href={url({ audience: 'individual' })}
                aria-current={audience === 'individual'}
              >
                {S.catalog.audienceIndividual}
              </Link>
            </div>
          </div>
        ) : null}

        {!locked.includes('category') ? (
          <div className="filters__group">
            <div className="filters__label">{S.catalog.filterCategory}</div>
            <div className="filters__list">
              <Link href={url({ category: undefined })} aria-current={!category}>
                {S.catalog.all}
              </Link>
              {categories.map((c) => (
                <Link
                  key={c.id}
                  href={url({ category: c.slug })}
                  aria-current={category === c.slug}
                >
                  {c.name_ar}
                </Link>
              ))}
            </div>
          </div>
        ) : null}

        {!locked.includes('occasion') ? (
          <div className="filters__group">
            <div className="filters__label">{S.catalog.filterOccasion}</div>
            <div className="filters__list">
              <Link href={url({ occasion: undefined })} aria-current={!occasion}>
                {S.catalog.all}
              </Link>
              {occasions.map((o) => (
                <Link
                  key={o.id}
                  href={url({ occasion: o.slug })}
                  aria-current={occasion === o.slug}
                >
                  {o.name_ar}
                </Link>
              ))}
            </div>
          </div>
        ) : null}

        <div className="filters__group">
          <div className="filters__label">{S.catalog.filterMethod}</div>
          <div className="filters__list">
            <Link href={url({ method: undefined })} aria-current={!method}>
              {S.catalog.all}
            </Link>
            {methods.map((m) => (
              <Link key={m.code} href={url({ method: m.code })} aria-current={method === m.code}>
                {m.name_ar}
              </Link>
            ))}
          </div>
        </div>
      </aside>

      <div>
        <div className="row" style={{ marginBlockEnd: 16 }}>
          <span style={{ color: 'var(--ink-faint)', fontSize: '0.9rem' }}>
            <span className="num">{formatQty(products.length)}</span> {S.catalog.products}
          </span>
          <span className="spacer" />
          <span className="chip-row">
            {SORTS.map((s) => (
              <Link
                key={s.key}
                href={url({ sort: s.key === 'featured' ? undefined : s.key })}
                className={`chip${sort === s.key ? ' chip--on' : ''}`}
              >
                {s.label}
              </Link>
            ))}
          </span>
        </div>

        <ProductGrid
          products={products}
          cardSpecs={cardSpecs}
          currency={currency}
          emptyAction={
            hasFilters ? (
              <Link className="btn btn--ghost" href={filterUrl(basePath, {}, {})}>
                {S.catalog.clearFilters}
              </Link>
            ) : null
          }
        />
      </div>
    </div>
  );
}
