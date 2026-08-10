'use client';

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { computeQuote } from '@/lib/pricing.js';
import type { PriceBook, Quote } from '@/lib/pricing.types';
import { formatPiastres, formatQty } from '@/lib/money.js';
import { firstQuoteMessage } from '@/lib/quoteErrors';
import { getBasket, removeLine, clearBasket, setLastOrder, type BasketLine } from '@/lib/basket';
import { fetchPriceBook, submitOrder, type OrderCustomer } from '@/lib/orders';
import { isEgMobile, normalizePhone } from '@/lib/phone.js';
import { GOVERNORATES } from '@/lib/governorates';
import { S } from '@/lib/strings';

// سلة عرض السعر.
//
// Prices are RECOMPUTED here from a fresh quote_product() rather than read from
// the basket. A basket left open across a price change would otherwise show
// yesterday's number, and the customer would notice on the confirmation page
// instead of here. create_order_request() recomputes a third time and stores
// its own figures; this is courtesy, that is authority.

interface Priced {
  line: BasketLine;
  book: PriceBook | null;
  quote: Quote | null;
}

// "We could not reach the database" and "this product is gone" look identical
// if both end up as a null book, and they need opposite advice: one says wait,
// the other says remove the line. Worth the extra state.
type BookResult = { book: PriceBook | null; unreachable: boolean };

export default function QuoteBasket() {
  const router = useRouter();
  const [lines, setLines] = useState<BasketLine[]>([]);
  const [books, setBooks] = useState<Record<string, BookResult>>({});
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [form, setForm] = useState({
    customer_kind: 'company' as 'company' | 'individual',
    contact_name: '',
    contact_phone: '',
    contact_email: '',
    company_name: '',
    tax_id: '',
    governorate: '',
    area: '',
    address: '',
    needed_by: '',
    note: '',
    ip_confirmed: false,
    portfolio_consent: false,
  });

  useEffect(() => {
    const current = getBasket();
    setLines(current);

    const ids = [...new Set(current.map((l) => l.product_id))];
    if (!ids.length) {
      setLoading(false);
      return;
    }

    Promise.all(
      ids.map((id) =>
        fetchPriceBook(id)
          .then((book): BookResult => ({ book, unreachable: false }))
          .catch((): BookResult => ({ book: null, unreachable: true }))
      )
    )
      .then((result) => setBooks(Object.fromEntries(ids.map((id, i) => [id, result[i]]))))
      .finally(() => setLoading(false));
  }, []);

  const priced: Priced[] = useMemo(
    () =>
      lines.map((line) => {
        const book = books[line.product_id]?.book ?? null;
        return {
          line,
          book,
          quote: book
            ? computeQuote(book, {
                qty: line.qty,
                methodCode: line.method_code,
                colors: line.colors,
                positionIds: line.position_ids,
                optionItemIds: line.option_item_ids,
              })
            : null,
        };
      }),
    [lines, books]
  );

  const currency = priced.find((p) => p.book)?.book?.currency ?? S.common.currency;
  const totals = priced.reduce(
    (acc, p) => ({
      subtotal: acc.subtotal + (p.quote?.subtotal ?? 0),
      setup: acc.setup + (p.quote?.setupTotal ?? 0),
      vat: acc.vat + (p.quote?.vatAmount ?? 0),
      total: acc.total + (p.quote?.total ?? 0),
    }),
    { subtotal: 0, setup: 0, vat: 0, total: 0 }
  );

  const broken = priced.filter((p) => !p.book || !p.quote?.ok);
  const canSend =
    lines.length > 0 &&
    broken.length === 0 &&
    form.contact_name.trim().length >= 3 &&
    isEgMobile(form.contact_phone) &&
    form.ip_confirmed;

  async function send() {
    setError(null);
    setSending(true);
    try {
      const customer: OrderCustomer = {
        customer_kind: form.customer_kind,
        contact_name: form.contact_name.trim(),
        contact_phone: normalizePhone(form.contact_phone),
        contact_email: form.contact_email.trim() || null,
        company_name: form.company_name.trim() || null,
        tax_id: form.tax_id.trim() || null,
        governorate: form.governorate || null,
        area: form.area.trim() || null,
        address: form.address.trim() || null,
        needed_by: form.needed_by || null,
        ip_confirmed: form.ip_confirmed,
        portfolio_consent: form.portfolio_consent,
        note: form.note.trim() || null,
      };

      const result = await submitOrder(customer, lines, totals.total / 100);

      setLastOrder({
        id: result.id,
        code: result.code,
        phone: customer.contact_phone,
        total: Number(result.total),
        at: new Date().toISOString(),
      });
      clearBasket();
      router.push('/quote/sent');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'حصلت مشكلة، جرّب تاني');
      setSending(false);
    }
  }

  if (loading) {
    return <p className="empty">بنحسب الأسعار…</p>;
  }

  if (!lines.length) {
    return (
      <div className="empty">
        <h2>عرض السعر فاضي</h2>
        <p>اختار منتج، ظبّط الكمية والطباعة، واضغط «أضف لعرض السعر».</p>
        <div className="row" style={{ justifyContent: 'center', marginBlockStart: 16 }}>
          <Link href="/corporate" className="btn btn--brand">
            {S.nav.corporate}
          </Link>
          <Link href="/gifts" className="btn btn--ghost">
            {S.nav.gifts}
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="quote">
      <div>
        {priced.map(({ line, book, quote }) => (
          <article key={line.key} className="quote__line">
            <div className="quote__line-head">
              <Link href={`/p/${line.slug}`} className="quote__line-name">
                {line.name_ar}
              </Link>
              <button
                type="button"
                className="cfg__file-x"
                aria-label={`شيل ${line.name_ar}`}
                onClick={() => setLines(removeLine(line.key))}
              >
                ✕
              </button>
            </div>

            <div className="quote__line-specs">
              <span className="num">{formatQty(line.qty)}</span> قطعة
              {line.method_code && book ? (
                <>
                  {' · '}
                  {book.methods.find((m) => m.code === line.method_code)?.name_ar}
                  {line.colors > 1 ? (
                    <>
                      {' '}
                      (<span className="num">{line.colors}</span> ألوان)
                    </>
                  ) : null}
                </>
              ) : null}
              {book && line.position_ids.length ? (
                <>
                  {' · '}
                  {line.position_ids
                    .map((id) => book.positions.find((p) => p.id === id)?.name_ar)
                    .filter(Boolean)
                    .join(' + ')}
                </>
              ) : null}
            </div>

            {line.texts.length ? (
              <div className="quote__line-specs">
                النص: {line.texts.map((t) => t.content).join(' / ')}
              </div>
            ) : null}
            {line.asset_paths.length ? (
              <div className="quote__line-specs">
                مرفق <span className="num">{line.asset_paths.length}</span> ملف تصميم
              </div>
            ) : null}

            {!book ? (
              <p className="notice notice--warn">
                {books[line.product_id]?.unreachable
                  ? 'مش قادرين نجيب السعر دلوقتي — اتأكد من النت وحدّث الصفحة.'
                  : 'المنتج ده مش متاح دلوقتي — شيله من عرض السعر عشان تكمل.'}
              </p>
            ) : !quote?.ok ? (
              <p className="notice notice--warn">{firstQuoteMessage(quote?.errors ?? [])}</p>
            ) : (
              <div className="quote__line-total">
                <span className="cfg__hint">
                  {formatPiastres(quote.unitPrice, currency)} للقطعة
                  {quote.setupTotal > 0
                    ? ` + ${formatPiastres(quote.setupTotal, currency)} تجهيز`
                    : ''}
                </span>
                <strong className="num">
                  {formatPiastres(quote.subtotal + quote.setupTotal, currency)}
                </strong>
              </div>
            )}
          </article>
        ))}

        <div className="quote__totals">
          <div className="cfg__line">
            <span>الإجمالي قبل الضريبة</span>
            <span className="num">
              {formatPiastres(totals.subtotal + totals.setup, currency)}
            </span>
          </div>
          {totals.vat > 0 ? (
            <div className="cfg__line cfg__line--soft">
              <span>ضريبة القيمة المضافة</span>
              <span className="num">{formatPiastres(totals.vat, currency)}</span>
            </div>
          ) : null}
          <div className="cfg__total">
            <span>الإجمالي</span>
            <strong className="num">{formatPiastres(totals.total, currency)}</strong>
          </div>
        </div>
      </div>

      {/* ------------------------------------------------------------ form -- */}
      <div className="panel quote__form">
        <div className="panel__title">بياناتك</div>

        <div className="chip-row" style={{ marginBlockEnd: 14 }}>
          {(['company', 'individual'] as const).map((k) => (
            <button
              key={k}
              type="button"
              aria-pressed={form.customer_kind === k}
              className={`chip${form.customer_kind === k ? ' chip--on' : ''}`}
              onClick={() => setForm({ ...form, customer_kind: k })}
            >
              {k === 'company' ? 'شركة' : 'فرد'}
            </button>
          ))}
        </div>

        <label className="field">
          <span>الاسم *</span>
          <input
            type="text"
            value={form.contact_name}
            onChange={(e) => setForm({ ...form, contact_name: e.target.value })}
          />
        </label>

        <label className="field">
          <span>الموبايل *</span>
          <input
            type="tel"
            inputMode="numeric"
            dir="ltr"
            placeholder="01xxxxxxxxx"
            value={form.contact_phone}
            onChange={(e) => setForm({ ...form, contact_phone: e.target.value })}
          />
          {form.contact_phone && !isEgMobile(form.contact_phone) ? (
            <span className="field__error">
              رقم مصري بيبدأ بـ 010 أو 011 أو 012 أو 015
            </span>
          ) : null}
        </label>

        {form.customer_kind === 'company' ? (
          <>
            <label className="field">
              <span>اسم الشركة</span>
              <input
                type="text"
                value={form.company_name}
                onChange={(e) => setForm({ ...form, company_name: e.target.value })}
              />
            </label>
            <label className="field">
              {/* Collected here, not on the phone later: a corporate invoice
                  needs it and chasing it afterwards costs a call. */}
              <span>الرقم الضريبي (لو محتاج فاتورة ضريبية)</span>
              <input
                type="text"
                dir="ltr"
                value={form.tax_id}
                onChange={(e) => setForm({ ...form, tax_id: e.target.value })}
              />
            </label>
          </>
        ) : null}

        <label className="field">
          <span>الإيميل</span>
          <input
            type="email"
            dir="ltr"
            value={form.contact_email}
            onChange={(e) => setForm({ ...form, contact_email: e.target.value })}
          />
        </label>

        <label className="field">
          <span>المحافظة</span>
          <select
            value={form.governorate}
            onChange={(e) => setForm({ ...form, governorate: e.target.value })}
          >
            <option value="">اختار</option>
            {GOVERNORATES.map((g) => (
              <option key={g} value={g}>
                {g}
              </option>
            ))}
          </select>
        </label>

        <label className="field">
          <span>العنوان</span>
          <input
            type="text"
            value={form.address}
            onChange={(e) => setForm({ ...form, address: e.target.value })}
          />
        </label>

        <label className="field">
          {/* The most useful field after the phone: it decides whether the job
              is possible at all before anybody quotes it. */}
          <span>محتاجه قبل تاريخ</span>
          <input
            type="date"
            dir="ltr"
            value={form.needed_by}
            onChange={(e) => setForm({ ...form, needed_by: e.target.value })}
          />
        </label>

        <label className="field">
          <span>ملاحظات</span>
          <textarea
            rows={3}
            value={form.note}
            onChange={(e) => setForm({ ...form, note: e.target.value })}
          />
        </label>

        <label className="check">
          <input
            type="checkbox"
            checked={form.ip_confirmed}
            onChange={(e) => setForm({ ...form, ip_confirmed: e.target.checked })}
          />
          <span>
            أقر بأن لي حق استخدام الشعار أو التصميم المرفوع، وأتحمّل مسؤولية ذلك. *
          </span>
        </label>

        <label className="check">
          {/* Separate consent on purpose: using a client's logo in our own
              portfolio is a different act from printing it for them. */}
          <input
            type="checkbox"
            checked={form.portfolio_consent}
            onChange={(e) => setForm({ ...form, portfolio_consent: e.target.checked })}
          />
          <span>أوافق على عرض شغلي ضمن أعمال نكست كامباين (اختياري)</span>
        </label>

        {error ? <p className="notice notice--warn">{error}</p> : null}

        <button
          type="button"
          className="btn btn--brand"
          style={{ inlineSize: '100%', marginBlockStart: 8 }}
          disabled={!canSend || sending}
          onClick={send}
        >
          {sending ? 'بنسجّل الطلب…' : 'ابعت الطلب'}
        </button>

        <p className="cfg__hint" style={{ marginBlockStart: 10 }}>
          بعد الإرسال هيوصلك رقم طلب، وهنفتح لك واتساب برسالة جاهزة. ملفاتك
          محفوظة معانا مع الطلب.
        </p>
      </div>
    </div>
  );
}
