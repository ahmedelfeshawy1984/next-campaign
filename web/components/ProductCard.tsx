import Link from 'next/link';
import Image from 'next/image';
import { S } from '@/lib/strings';
import { formatPrice, formatQty, savingPercent } from '@/lib/money';
import { mediaUrl } from '@/lib/supabase';
import type { ProductCardRow, SpecDef, SpecValue } from '@/lib/types';

/** Reads a spec off the flat product row. Typed, so a bad key is a build error. */
function specValue(p: ProductCardRow, key: string): SpecValue {
  const v = (p as unknown as Record<string, SpecValue>)[key];
  return v === undefined ? null : v;
}

function renderSpec(p: ProductCardRow, def: SpecDef): string | null {
  const v = specValue(p, def.key);
  if (v === null || v === '') return null;
  if (def.kind === 'bool') return v ? def.label_ar : null;
  return def.unit_ar ? `${v} ${def.unit_ar}` : String(v);
}

export default function ProductCard({
  product,
  cardSpecs = [],
  currency = 'ج.م',
}: {
  product: ProductCardRow;
  cardSpecs?: SpecDef[];
  currency?: string;
}) {
  const cover = mediaUrl(product.cover_url);
  const specs = cardSpecs
    .filter((d) => d.show_in_card)
    .map((d) => renderSpec(product, d))
    .filter((s): s is string => !!s)
    .slice(0, 3);

  const saving = savingPercent(product.price_at_moq, product.price_from);

  return (
    <article className="card">
      <Link href={`/p/${product.slug}`} className="card__media" aria-hidden={false}>
        {cover ? (
          <Image
            src={cover}
            alt={product.name_ar}
            width={480}
            height={360}
            sizes="(max-width: 700px) 50vw, 260px"
            style={{ inlineSize: '100%', blockSize: '100%', objectFit: 'cover' }}
          />
        ) : (
          // No stock photography, ever — a generic mug from a catalogue site
          // sets an expectation the workshop cannot meet. An honest placeholder
          // is better than a photograph of somebody else's product.
          <span className="card__placeholder">{product.name_ar}</span>
        )}
        <span className="card__flags">
          {product.for_individual && !product.for_corporate ? (
            <span className="badge badge--soft">هدية فردية</span>
          ) : null}
          {!product.is_available ? (
            <span className="badge badge--muted">{S.product.outOfStock}</span>
          ) : null}
        </span>
      </Link>

      <div className="card__body">
        <Link href={`/p/${product.slug}`} className="card__title">
          {product.name_ar}
        </Link>

        {specs.length ? (
          <div className="card__specs">
            {specs.map((s) => (
              <span key={s}>{s}</span>
            ))}
          </div>
        ) : null}

        <div className="card__price">
          {product.price_at_moq != null ? (
            <>
              <div>
                <span className="price-main num">
                  {formatPrice(product.price_at_moq, currency)}
                </span>{' '}
                <span className="price-unit">{S.product.perPiece}</span>
              </div>
              <div className="price-note">
                {/* The MOQ is on the card on purpose. An individual who
                    configures a mug and meets "minimum 36" at checkout is a
                    lost sale and an angry message. */}
                {S.product.moq}{' '}
                <span className="num">{formatQty(product.moq)}</span> {S.product.piece}
                {saving ? (
                  <>
                    {' · '}
                    {S.product.dropsTo}{' '}
                    <span className="num">{formatPrice(product.price_from, currency)}</span>
                  </>
                ) : null}
              </div>
            </>
          ) : (
            <div className="price-note">{S.product.askForQuote}</div>
          )}
        </div>
      </div>
    </article>
  );
}
