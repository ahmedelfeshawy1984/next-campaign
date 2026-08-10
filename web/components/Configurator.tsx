'use client';

import { useCallback, useMemo, useState } from 'react';
import { usePathname, useRouter, useSearchParams } from 'next/navigation';
import { S } from '@/lib/strings';
import {
  computeQuote,
  maxColorsAt,
  nextRungSaving,
  positionAllowsMethod,
  tierFor,
} from '@/lib/pricing.js';
import type { PriceBook, Quote, Selection } from '@/lib/pricing.types';
import { formatPiastres, formatQty, toPiastres, formatPrice } from '@/lib/money.js';
import { firstQuoteMessage } from '@/lib/quoteErrors';
import dynamic from 'next/dynamic';
import type { UploadedAsset } from '@/lib/uploads';
import { addLine } from '@/lib/basket';

// Loaded ON DEMAND, and that is a size decision rather than a style one.
//
// The uploader pulls in @supabase/supabase-js (session + storage), which is
// ~70 kB — two thirds again on top of the whole product page. Most visitors
// configure and look at the price without ever uploading anything, and this is
// the page they arrive on from a WhatsApp link, on mobile data. So the module
// waits until somebody says they want to upload.
const LogoUploader = dynamic(() => import('./LogoUploader'), {
  ssr: false,
  loading: () => <p className="cfg__hint">لحظة…</p>,
});

// بانل التخصيص — the thing the whole site exists for.
//
// The total is computed IN THE BROWSER on every keystroke, over the price book
// the server already sent. No round trip, no spinner, no "request a quote and
// wait". price_quote() in SQL stays the authority and recomputes on submit
// (P3); this is the same arithmetic over the same data — the harness proves it
// to the piastre on 200 random selections.

interface Props {
  book: PriceBook;
  coverUrl: string | null;
}

/** Price-affecting state lives in the URL; personal text does not. See below. */
function readSelection(sp: URLSearchParams, book: PriceBook): Selection {
  const list = (key: string) =>
    (sp.get(key) ?? '').split(',').map((s) => s.trim()).filter(Boolean);

  const defaultMethod = book.methods.find((m) => m.is_default) ?? book.methods[0] ?? null;
  const defaultPosition = book.positions.find((p) => p.is_default) ?? book.positions[0];

  const qtyRaw = Number(sp.get('qty'));
  const positions = list('pos');
  const options = list('opt');

  return {
    qty: Number.isFinite(qtyRaw) && qtyRaw >= 1 ? Math.floor(qtyRaw) : book.moq,
    methodCode: sp.get('m') ?? defaultMethod?.code ?? null,
    colors: Math.max(1, Number(sp.get('c')) || 1),
    positionIds: positions.length ? positions : defaultPosition ? [defaultPosition.id] : [],
    optionItemIds: options.length
      ? options
      : // Pre-select the first available item of each required group, so the
        // opening price is a real price rather than one the customer has to
        // earn by clicking.
        book.option_groups
          .filter((g) => g.is_required)
          .map((g) => g.items.find((i) => i.is_available)?.id)
          .filter((v): v is string => !!v),
  };
}

export default function Configurator({ book, coverUrl }: Props) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();

  const sel = useMemo(
    () => readSelection(new URLSearchParams(searchParams.toString()), book),
    [searchParams, book]
  );

  // Text and font are NOT in the URL. Everything that changes the price is, so
  // a configured product is a link a purchasing manager can forward to their
  // boss and the boss sees the same total. A love note or a staff name is not
  // something to put in a URL somebody might share.
  const [textLines, setTextLines] = useState<string[]>(() =>
    Array.from({ length: Math.min(book.max_text_lines, 3) }, () => '')
  );
  const [fontKey, setFontKey] = useState<string>(() => book.fonts[0]?.key ?? '');
  const [previewPositionId, setPreviewPositionId] = useState<string | null>(null);
  const [assets, setAssets] = useState<UploadedAsset[]>([]);
  const [wantsUpload, setWantsUpload] = useState(false);
  const [added, setAdded] = useState(false);

  const patch = useCallback(
    (next: Partial<Record<'qty' | 'm' | 'c' | 'pos' | 'opt', string | null>>) => {
      const sp = new URLSearchParams(searchParams.toString());
      for (const [k, v] of Object.entries(next)) {
        if (v === null || v === '') sp.delete(k);
        else sp.set(k, v);
      }
      // replace, not push: dragging the quantity must not fill the back button
      // with forty history entries.
      router.replace(`${pathname}?${sp.toString()}`, { scroll: false });
    },
    [router, pathname, searchParams]
  );

  const quote: Quote = useMemo(() => computeQuote(book, sel), [book, sel]);
  const method = book.methods.find((m) => m.code === sel.methodCode) ?? null;
  const saving = nextRungSaving(book, sel);
  const message = firstQuoteMessage(quote.errors);

  const activePosition =
    book.positions.find((p) => p.id === (previewPositionId ?? sel.positionIds[0])) ?? null;

  const colorCeiling = method
    ? maxColorsAt(book, method.code, sel.positionIds[0]) ?? 8
    : 1;

  const setPositions = (ids: string[]) => patch({ pos: ids.join(',') || null });

  const togglePosition = (id: string) => {
    const on = sel.positionIds.includes(id);
    if (on) {
      // Never leave zero positions — a print with nowhere to go is not a state
      // the customer meant to reach.
      if (sel.positionIds.length === 1) return;
      setPositions(sel.positionIds.filter((p) => p !== id));
    } else {
      if (sel.positionIds.length >= book.max_positions) {
        // At the ceiling, a tap REPLACES the oldest rather than doing nothing.
        setPositions([...sel.positionIds.slice(1), id]);
      } else {
        setPositions([...sel.positionIds, id]);
      }
    }
  };

  const chooseOption = (groupId: string, itemId: string) => {
    const group = book.option_groups.find((g) => g.id === groupId);
    if (!group) return;
    const others = sel.optionItemIds.filter(
      (id) => !group.items.some((i) => i.id === id)
    );
    patch({ opt: [...others, itemId].join(',') });
  };

  const currentTier = tierFor(book.tiers, sel.qty);

  return (
    <div className="cfg">
      {/* ------------------------------------------------------ preview -- */}
      {coverUrl && activePosition?.preview_w ? (
        <div className="cfg__preview">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={coverUrl} alt={book.name_ar} />
          <div
            className="cfg__stamp"
            style={{
              insetInlineStart: `${Number(activePosition.preview_x)}%`,
              insetBlockStart: `${Number(activePosition.preview_y)}%`,
              inlineSize: `${Number(activePosition.preview_w)}%`,
              blockSize: `${Number(activePosition.preview_h)}%`,
              rotate: `${Number(activePosition.preview_rotate)}deg`,
              fontFamily: book.fonts.find((f) => f.key === fontKey)?.css_family,
            }}
          >
            {textLines.filter(Boolean).map((line, i) => (
              <span key={i}>{line}</span>
            ))}
          </div>
          <p className="cfg__preview-note">
            معاينة تقريبية — المعاينة النهائية بتوصلك قبل التنفيذ
          </p>
        </div>
      ) : null}

      {/* ----------------------------------------------------- quantity -- */}
      <section className="cfg__block">
        <h3 className="cfg__label">{S.product.quantity}</h3>
        <div className="cfg__qty">
          <button
            type="button"
            className="btn btn--ghost"
            aria-label="أقل"
            onClick={() => patch({ qty: String(Math.max(book.moq, sel.qty - book.moq)) })}
          >
            −
          </button>
          <input
            className="num"
            type="number"
            min={book.moq}
            value={sel.qty}
            aria-label={S.product.quantity}
            onChange={(e) => patch({ qty: e.target.value })}
          />
          <button
            type="button"
            className="btn btn--ghost"
            aria-label="أكتر"
            onClick={() => patch({ qty: String(sel.qty + book.moq) })}
          >
            +
          </button>
          <span className="cfg__hint">
            {S.product.moq} <span className="num">{formatQty(book.moq)}</span>
          </span>
        </div>

        <div className="cfg__ladder">
          {book.tiers.map((t) => {
            const on = currentTier?.min_qty === t.min_qty;
            return (
              <button
                key={t.min_qty}
                type="button"
                className={`cfg__rung${on ? ' cfg__rung--on' : ''}`}
                onClick={() => patch({ qty: String(t.min_qty) })}
              >
                <span className="num">{formatQty(t.min_qty)}+</span>
                <strong className="num">{formatPrice(t.unit_price, book.currency)}</strong>
              </button>
            );
          })}
        </div>

        {saving ? (
          // The highest-converting sentence on the page: it turns a browser
          // into a bigger order, and it is computed from the ladder rather
          // than written by anyone.
          <button
            type="button"
            className="cfg__nudge"
            onClick={() => patch({ qty: String(saving.atQty) })}
          >
            خُد <span className="num">{formatQty(saving.atQty)}</span> ووفّر{' '}
            <span className="num">{saving.percent}%</span> في سعر القطعة
          </button>
        ) : null}
      </section>

      {/* ------------------------------------------------------ options -- */}
      {book.option_groups.map((g) => (
        <section className="cfg__block" key={g.id}>
          <h3 className="cfg__label">{g.label_ar}</h3>
          <div className={g.items.some((i) => i.hex) ? 'swatches' : 'chip-row'}>
            {g.items.map((i) => {
              const on = sel.optionItemIds.includes(i.id);
              const label =
                toPiastres(i.price_delta) > 0
                  ? `${i.label_ar} +${formatPrice(i.price_delta, book.currency)}`
                  : i.label_ar;

              return i.hex ? (
                <button
                  key={i.id}
                  type="button"
                  title={i.is_available ? label : `${i.label_ar} — ${S.product.outOfStock}`}
                  aria-label={label}
                  aria-pressed={on}
                  disabled={!i.is_available}
                  className={`swatch${on ? ' swatch--on' : ''}${i.is_available ? '' : ' swatch--out'}`}
                  style={{ background: i.hex }}
                  onClick={() => chooseOption(g.id, i.id)}
                />
              ) : (
                <button
                  key={i.id}
                  type="button"
                  aria-pressed={on}
                  disabled={!i.is_available}
                  className={`chip${on ? ' chip--on' : ''}`}
                  onClick={() => chooseOption(g.id, i.id)}
                >
                  {label}
                </button>
              );
            })}
          </div>
        </section>
      ))}

      {/* ------------------------------------------------------- method -- */}
      {book.methods.length ? (
        <section className="cfg__block">
          <h3 className="cfg__label">{S.product.printMethods}</h3>
          <div className="cfg__methods">
            {book.methods.map((m) => {
              const tooFew = m.method_min_qty != null && sel.qty < m.method_min_qty;
              const on = sel.methodCode === m.code;
              return (
                <button
                  key={m.code}
                  type="button"
                  aria-pressed={on}
                  className={`cfg__method${on ? ' cfg__method--on' : ''}`}
                  onClick={() => patch({ m: m.code, c: '1' })}
                >
                  <strong>{m.name_ar}</strong>
                  <span className="cfg__method-fee">
                    {toPiastres(m.setup_fee) > 0
                      ? `${S.product.setupFee} ${formatPrice(m.setup_fee, book.currency)}${
                          m.setup_fee_per_color ? ' لكل لون' : ''
                        }`
                      : 'من غير كليشيه'}
                  </span>
                  {/* A disabled control must say WHY. "Not available" with no
                      reason reads as a broken site. */}
                  {tooFew ? (
                    <span className="cfg__method-warn">
                      حد أدنى <span className="num">{formatQty(m.method_min_qty)}</span> قطعة
                    </span>
                  ) : null}
                  {m.needs_vector ? (
                    <span className="cfg__method-warn">{S.product.needsVector}</span>
                  ) : null}
                </button>
              );
            })}
          </div>
        </section>
      ) : null}

      {/* ----------------------------------------------------- positions -- */}
      {book.positions.length ? (
        <section className="cfg__block">
          <h3 className="cfg__label">
            {S.product.printPositions}
            {book.max_positions > 1 ? (
              <span className="cfg__hint">
                {' '}
                لحد <span className="num">{book.max_positions}</span> أماكن
              </span>
            ) : null}
          </h3>
          <div className="chip-row">
            {book.positions.map((p) => {
              const on = sel.positionIds.includes(p.id);
              const allowed = !method || positionAllowsMethod(p, method.code);
              return (
                <button
                  key={p.id}
                  type="button"
                  aria-pressed={on}
                  disabled={!allowed}
                  className={`chip${on ? ' chip--on' : ''}`}
                  onMouseEnter={() => setPreviewPositionId(p.id)}
                  onFocus={() => setPreviewPositionId(p.id)}
                  onClick={() => togglePosition(p.id)}
                  title={allowed ? undefined : 'الطريقة اللي اخترتها مش بتشتغل على المكان ده'}
                >
                  {p.name_ar}
                  {p.area_w_mm && p.area_h_mm ? (
                    <span className="num" dir="ltr" style={{ color: 'var(--ink-faint)' }}>
                      {Number(p.area_w_mm)}×{Number(p.area_h_mm)}
                    </span>
                  ) : null}
                </button>
              );
            })}
          </div>
        </section>
      ) : null}

      {/* -------------------------------------------------------- colours -- */}
      {method?.uses_color_count ? (
        <section className="cfg__block">
          <h3 className="cfg__label">
            عدد ألوان {method.color_model === 'thread' ? 'الخيط' : 'الطباعة'}
          </h3>
          <div className="chip-row">
            {Array.from({ length: colorCeiling }, (_, i) => i + 1).map((n) => (
              <button
                key={n}
                type="button"
                aria-pressed={sel.colors === n}
                className={`chip${sel.colors === n ? ' chip--on' : ''}`}
                onClick={() => patch({ c: String(n) })}
              >
                <span className="num">{n}</span>
              </button>
            ))}
          </div>
          <p className="cfg__hint">
            لون واحد أرخص — كل لون زيادة بيضيف كليشيه وسعر على القطعة.
          </p>
        </section>
      ) : method ? (
        <p className="notice">
          {method.color_model === 'single_tone'
            ? 'الطريقة دي بتشتغل على الخامة نفسها — مفيش اختيار ألوان، والنتيجة بلون المعدن أو الخامة.'
            : 'الطريقة دي بألوان كاملة — سعر واحد مهما كان عدد ألوان التصميم.'}
        </p>
      ) : null}

      {/* ----------------------------------------------------------- text -- */}
      {book.allows_text && book.max_text_lines > 0 ? (
        <section className="cfg__block">
          <h3 className="cfg__label">الكلام اللي هيتطبع</h3>
          {textLines.slice(0, book.max_text_lines).map((line, i) => (
            <input
              key={i}
              className="cfg__text"
              type="text"
              maxLength={60}
              value={line}
              placeholder={i === 0 ? 'الاسم أو اسم الشركة' : 'سطر إضافي (اختياري)'}
              aria-label={`سطر ${i + 1}`}
              onChange={(e) => {
                const next = [...textLines];
                next[i] = e.target.value;
                setTextLines(next);
              }}
            />
          ))}

          {book.fonts.length ? (
            <div className="cfg__fonts">
              {book.fonts.map((f) => (
                <button
                  key={f.key}
                  type="button"
                  aria-pressed={fontKey === f.key}
                  className={`cfg__font${fontKey === f.key ? ' cfg__font--on' : ''}`}
                  style={{ fontFamily: f.css_family }}
                  onClick={() => setFontKey(f.key)}
                >
                  {f.name_ar}
                </button>
              ))}
            </div>
          ) : null}
        </section>
      ) : null}

      {/* ----------------------------------------------------------- logo -- */}
      {book.allows_logo ? (
        <section className="cfg__block">
          <h3 className="cfg__label">اللوجو أو التصميم</h3>
          {wantsUpload || assets.length ? (
            <LogoUploader
              assets={assets}
              onChange={setAssets}
              areaWidthMm={
                activePosition?.area_w_mm != null ? Number(activePosition.area_w_mm) : null
              }
              needsVector={method?.needs_vector}
            />
          ) : (
            <button
              type="button"
              className="cfg__drop"
              onClick={() => setWantsUpload(true)}
            >
              ارفع اللوجو أو التصميم
              <span className="cfg__hint">
                AI · EPS · PDF · PNG · JPG — لحد ٢٠ ميجا
              </span>
            </button>
          )}
        </section>
      ) : null}

      {/* -------------------------------------------------------- summary -- */}
      <div className="cfg__summary">
        {message ? <p className="notice notice--warn">{message}</p> : null}

        <div className="cfg__line">
          <span>سعر القطعة</span>
          <strong className="num">{formatPiastres(quote.unitPrice, book.currency)}</strong>
        </div>
        <div className="cfg__line cfg__line--soft">
          <span>
            <span className="num">{formatQty(quote.qty)}</span> قطعة
          </span>
          <span className="num">{formatPiastres(quote.subtotal, book.currency)}</span>
        </div>
        {quote.setupTotal > 0 ? (
          <div className="cfg__line cfg__line--soft">
            <span>
              {S.product.setupFee} ({S.product.setupFeeOnce})
            </span>
            <span className="num">{formatPiastres(quote.setupTotal, book.currency)}</span>
          </div>
        ) : null}
        {quote.vatAmount > 0 ? (
          <div className="cfg__line cfg__line--soft">
            <span>ضريبة القيمة المضافة</span>
            <span className="num">{formatPiastres(quote.vatAmount, book.currency)}</span>
          </div>
        ) : null}

        <div className="cfg__total">
          <span>الإجمالي</span>
          <strong className="num">{formatPiastres(quote.total, book.currency)}</strong>
        </div>

        {book.lead_days_min ? (
          <p className="cfg__hint">
            التنفيذ{' '}
            <span className="num">
              {book.lead_days_min}
              {book.lead_days_max ? `–${book.lead_days_max}` : ''}
            </span>{' '}
            يوم عمل من اعتماد المعاينة
          </p>
        ) : null}

        <button
          type="button"
          className="btn btn--brand"
          style={{ inlineSize: '100%', marginBlockStart: 14 }}
          // Disabled while the configuration is invalid, and the reason is
          // already printed above — never a dead button with no explanation.
          disabled={!quote.ok}
          onClick={() => {
            addLine({
              product_id: book.product_id,
              slug: book.slug,
              name_ar: book.name_ar,
              cover_url: coverUrl,
              qty: sel.qty,
              method_code: sel.methodCode,
              colors: sel.colors,
              position_ids: sel.positionIds,
              option_item_ids: sel.optionItemIds,
              texts: textLines
                .map((content, i) => ({ slot: i + 1, content, font_key: fontKey || null }))
                .filter((t) => t.content.trim() !== ''),
              asset_paths: assets.map((a) => a.path),
            });
            setAdded(true);
          }}
        >
          أضف لعرض السعر
        </button>

        {added ? (
          <p className="cfg__added">
            اتضاف ✓{' '}
            <a href="/quote" className="btn btn--ghost btn--sm">
              افتح عرض السعر
            </a>{' '}
            <button
              type="button"
              className="btn btn--ghost btn--sm"
              onClick={() => setAdded(false)}
            >
              ضيف منتج تاني
            </button>
          </p>
        ) : null}
      </div>
    </div>
  );
}
