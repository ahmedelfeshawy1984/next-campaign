import type { Metadata } from 'next';
import { Suspense } from 'react';
import Link from 'next/link';
import Image from 'next/image';
import { notFound, redirect } from 'next/navigation';
import { S } from '@/lib/strings';
import {
  getProductBySlug,
  getRelatedProducts,
  getSiteSettings,
  getSpecsForCategory,
  resolveSlugAlias,
  getAllRoutes,
} from '@/lib/queries';
import { mediaUrl } from '@/lib/supabase';
import { absoluteUrl } from '@/lib/env';
import { formatPrice, formatQty } from '@/lib/money.js';
import PriceLadder from '@/components/PriceLadder';
import SpecSheet from '@/components/SpecSheet';
import ProductGrid from '@/components/ProductGrid';
import Configurator from '@/components/Configurator';
import { getPriceBook } from '@/lib/queries';
import type { ProductDetailRow } from '@/lib/types';

export const revalidate = 300;

export async function generateStaticParams() {
  const { products } = await getAllRoutes().catch(() => ({ products: [] as { slug: string }[] }));
  return products.map((p) => ({ slug: p.slug }));
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const product = await getProductBySlug(slug).catch(() => null);
  if (!product) return {};

  const title = product.seo_title_ar ?? product.name_ar;
  const description =
    product.seo_desc_ar ??
    product.short_pitch_ar ??
    product.description_ar?.slice(0, 155) ??
    undefined;

  // og:image is the PRODUCT PHOTO, not a composed card.
  //
  // next/og (Satori) shapes Arabic badly — a generated card renders the letters
  // disconnected, which is worse than no card and would be discovered by the
  // owner, on WhatsApp, in front of a client. A composed card is a later
  // nicety; the photograph works today.
  const cover = mediaUrl(product.cover_url);

  return {
    title,
    description,
    alternates: { canonical: `/p/${product.slug}` },
    openGraph: {
      type: 'website',
      title,
      description,
      url: `/p/${product.slug}`,
      images: cover ? [{ url: cover, alt: product.name_ar }] : undefined,
    },
    twitter: { card: cover ? 'summary_large_image' : 'summary', title, description },
  };
}

function jsonLd(product: ProductDetailRow, currency: string) {
  const cover = mediaUrl(product.cover_url);
  return {
    '@context': 'https://schema.org',
    '@type': 'Product',
    name: product.name_ar,
    description: product.description_ar ?? product.short_pitch_ar ?? undefined,
    sku: product.sku ?? undefined,
    image: cover ? [cover] : undefined,
    category: product.categories?.name_ar,
    url: absoluteUrl(`/p/${product.slug}`),
    ...(product.price_at_moq != null
      ? {
          offers: {
            '@type': 'Offer',
            // The MOQ price, not the thousand-piece price. Publishing the
            // cheapest rung as "the price" is the same lie in structured data
            // that it is on the card.
            price: Number(product.price_at_moq),
            priceCurrency: 'EGP',
            availability: product.is_available
              ? 'https://schema.org/InStock'
              : 'https://schema.org/OutOfStock',
            eligibleQuantity: {
              '@type': 'QuantitativeValue',
              minValue: product.moq,
              unitText: currency ? 'قطعة' : undefined,
            },
          },
        }
      : {}),
  };
}

export default async function ProductPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  let product = await getProductBySlug(slug);

  if (!product) {
    // A link somebody shared two years ago still resolves. One table, one 301.
    const target = await resolveSlugAlias(slug).catch(() => null);
    if (target) redirect(`/p/${target}`);
    notFound();
  }
  product = product as ProductDetailRow;

  const [settings, specs, related, book] = await Promise.all([
    getSiteSettings(),
    getSpecsForCategory(product.category_id),
    getRelatedProducts(product, 4),
    getPriceBook(product.id),
  ]);

  const currency = settings?.currency ?? S.common.currency;
  const cover = mediaUrl(product.cover_url);
  const gallery = product.product_images.map((i) => mediaUrl(i.url)).filter(Boolean) as string[];
  const hero = cover ?? gallery[0] ?? null;

  const methods = product.product_print_methods;
  const needsVector = methods.some((m) => m.print_methods?.needs_vector);

  return (
    <>
      <script
        type="application/ld+json"
        // Structured data, not markup: the object is built in this file from
        // typed fields, never from user input.
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd(product, currency)) }}
      />

      <div className="wrap">
        <nav className="breadcrumbs" aria-label="مسار التنقل">
          <Link href="/">{S.nav.home}</Link>
          <span>›</span>
          {product.categories ? (
            <>
              <Link href={`/c/${product.categories.slug}`}>{product.categories.name_ar}</Link>
              <span>›</span>
            </>
          ) : null}
          {product.name_ar}
        </nav>

        <div className="product">
          <div>
            <div className="gallery__main">
              {hero ? (
                <Image
                  src={hero}
                  alt={product.name_ar}
                  width={900}
                  height={675}
                  priority
                  sizes="(max-width: 940px) 100vw, 700px"
                  style={{ inlineSize: '100%', blockSize: '100%', objectFit: 'contain' }}
                />
              ) : (
                <div className="gallery__empty">
                  لسه مفيش صورة للمنتج ده
                  <br />
                  <span style={{ fontSize: '0.82rem' }}>
                    بنصوّر المنتجات بنفسنا — مش بنستخدم صور جاهزة
                  </span>
                </div>
              )}
            </div>

            {gallery.length > 1 ? (
              <div className="grid" style={{ gridTemplateColumns: 'repeat(4, 1fr)', marginBlockStart: 12 }}>
                {gallery.slice(0, 8).map((url) => (
                  <div key={url} className="card__media" style={{ borderRadius: 10 }}>
                    <Image src={url} alt="" width={200} height={150} sizes="120px" />
                  </div>
                ))}
              </div>
            ) : null}

            <div className="panel" style={{ marginBlockStart: 20 }}>
              <div className="panel__title">{S.product.specs}</div>
              <SpecSheet product={product} defs={specs} />
            </div>

            {product.description_ar ? (
              <div className="panel">
                <div className="panel__title">عن المنتج</div>
                <p style={{ margin: 0, color: 'var(--ink-soft)' }}>{product.description_ar}</p>
              </div>
            ) : null}
          </div>

          <div>
            <h1 style={{ marginBlockEnd: 8 }}>{product.name_ar}</h1>
            {product.short_pitch_ar ? (
              <p className="lead" style={{ marginBlockEnd: 16 }}>
                {product.short_pitch_ar}
              </p>
            ) : null}

            {book ? (
              // The configurator IS the product page. Everything the old static
              // panels showed — price, ladder, methods, positions, options — is
              // in here, now connected to a total that moves.
              //
              // Suspense because it reads searchParams: the configuration lives
              // in the URL so a configured product is a link somebody can
              // forward, and useSearchParams would otherwise opt the whole page
              // out of static rendering.
              <Suspense
                fallback={
                  <div className="panel">
                    <div>
                      <span className="price-main num" style={{ fontSize: '1.6rem' }}>
                        {formatPrice(product.price_at_moq, currency)}
                      </span>{' '}
                      <span className="price-unit">{S.product.perPiece}</span>
                    </div>
                    <div className="price-note" style={{ marginBlockEnd: 14 }}>
                      {S.product.atMoq} — <span className="num">{formatQty(product.moq)}</span>{' '}
                      {S.product.piece}
                    </div>
                    <PriceLadder
                      tiers={product.product_price_tiers}
                      moq={product.moq}
                      currency={currency}
                    />
                  </div>
                }
              >
                <Configurator book={book} coverUrl={cover} />
              </Suspense>
            ) : (
              // No price book means the product is not orderable. Say so and
              // show the ladder we do have, rather than a dead control.
              <div className="panel">
                <PriceLadder
                  tiers={product.product_price_tiers}
                  moq={product.moq}
                  currency={currency}
                />
                <p className="notice" style={{ marginBlockStart: 12 }}>
                  {S.product.askForQuote}
                </p>
              </div>
            )}

            <p style={{ marginBlockStart: 12, fontSize: '0.84rem', color: 'var(--ink-faint)' }}>
              {settings?.prices_include_vat ? S.common.vatNoteIncluded : S.common.vatNote}
            </p>

            {needsVector ? (
              <p className="notice notice--warn" style={{ marginBlockStart: 12 }}>
                بعض طرق الطباعة دي محتاجة ملف vector (AI / EPS / PDF). لو معندكش،
                بنعمله لك.
              </p>
            ) : null}
          </div>
        </div>

        {related.length ? (
          <section className="section section--tight">
            <h2>{S.product.relatedTitle}</h2>
            <ProductGrid products={related} currency={currency} />
          </section>
        ) : null}
      </div>
    </>
  );
}
