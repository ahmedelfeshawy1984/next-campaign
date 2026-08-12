import Link from 'next/link';
import { S } from '@/lib/strings';
import { getCategories, getOccasions, getFeaturedProducts, getSiteSettings } from '@/lib/queries';
import ProductGrid from '@/components/ProductGrid';

export const revalidate = 300;

export default async function HomePage() {
  const [categories, occasions, featured, settings] = await Promise.all([
    getCategories(),
    getOccasions(),
    getFeaturedProducts(8),
    getSiteSettings(),
  ]);
  const currency = settings?.currency ?? S.common.currency;
  const topLevel = categories.filter((c) => !c.parent_id);

  return (
    <>
      <section className="hero">
        <div className="wrap hero__grid">
          <div>
            <p className="eyebrow">{settings?.tagline_ar ?? S.tagline}</p>
            <h1>{S.home.heroTitle}</h1>
            <p className="lead">{S.home.heroBody}</p>
            <div className="row" style={{ marginBlockStart: 22 }}>
              <Link href="/corporate" className="btn btn--brand">
                {S.home.corporateCta}
              </Link>
              <Link href="/gifts" className="btn btn--ghost">
                {S.home.giftsCta}
              </Link>
            </div>
            {settings?.quote_promise_ar ? (
              <p style={{ marginBlockStart: 16, color: 'var(--ink-faint)', fontSize: '0.9rem' }}>
                {settings.quote_promise_ar}
              </p>
            ) : null}
          </div>

          <div className="grid" style={{ gridTemplateColumns: '1fr 1fr', gap: 12 }}>
            {topLevel.slice(0, 6).map((c) => (
              <Link key={c.id} href={`/c/${c.slug}`} className="tile">
                <div className="tile__title">{c.name_ar}</div>
                {c.blurb_ar ? <div className="tile__blurb">{c.blurb_ar}</div> : null}
              </Link>
            ))}
          </div>
        </div>
      </section>

      {featured.length ? (
        <section className="section">
          <div className="wrap">
            <h2>{S.home.featuredTitle}</h2>
            <ProductGrid products={featured} currency={currency} />
          </div>
        </section>
      ) : null}

      {occasions.length ? (
        <section className="section section--surface">
          <div className="wrap">
            <h2>{S.home.occasionsTitle}</h2>
            <div className="chip-row" style={{ marginBlockStart: 14 }}>
              {occasions.map((o) => (
                <Link key={o.id} href={`/o/${o.slug}`} className="chip">
                  {o.name_ar}
                </Link>
              ))}
            </div>
          </div>
        </section>
      ) : null}

      <section className="section">
        <div className="wrap">
          <h2>{S.home.categoriesTitle}</h2>
          <div className="grid grid--wide" style={{ marginBlockStart: 14 }}>
            {topLevel.map((c) => (
              <Link key={c.id} href={`/c/${c.slug}`} className="tile">
                <div className="tile__title">{c.name_ar}</div>
                {c.blurb_ar ? <div className="tile__blurb">{c.blurb_ar}</div> : null}
              </Link>
            ))}
          </div>
        </div>
      </section>

      <section className="section section--surface">
        <div className="wrap">
          <h2>{S.home.howTitle}</h2>
          <div className="grid grid--wide steps" style={{ marginBlockStart: 14 }}>
            {S.home.steps.map((s) => (
              <div key={s.t} className="tile">
                <div className="tile__title">{s.t}</div>
                <div className="tile__blurb">{s.b}</div>
              </div>
            ))}
          </div>
        </div>
      </section>
    </>
  );
}
