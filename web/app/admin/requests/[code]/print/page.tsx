'use client';

import { useEffect, useState } from 'react';
import { useParams } from 'next/navigation';
import { fetchOrderByCode, type AdminOrder } from '@/lib/adminOrders';
import { formatQty } from '@/lib/money.js';
import { prettyPhone } from '@/lib/phone.js';

// أمر الشغل.
//
// One page, handed to the workshop. It is the screen that gets used every day,
// and the only one where leaving something out has a physical consequence.
//
// NO PRICES. The workshop needs to know what to make, not what it sold for, and
// a job sheet with a total on it ends up in front of a customer eventually.
//
// The text is printed large and alone, because that is the field that gets
// mistyped — a missing letter in a company name is a whole batch reprinted.

export default function JobSheet() {
  const { code } = useParams<{ code: string }>();
  const [order, setOrder] = useState<AdminOrder | null | undefined>(undefined);

  useEffect(() => {
    fetchOrderByCode(code).then(setOrder).catch(() => setOrder(null));
  }, [code]);

  if (order === undefined) return <p className="empty">لحظة…</p>;
  if (!order) return <p className="empty">مفيش طلب بالرقم ده.</p>;

  return (
    <div className="sheet">
      <div className="sheet__no-print row">
        <button type="button" className="btn btn--brand" onClick={() => window.print()}>
          اطبع
        </button>
        <span className="cfg__hint">الصفحة دي متظبطة للطباعة على A4.</span>
      </div>

      <header className="sheet__head">
        <div>
          <h1 className="num" dir="ltr">
            {order.code}
          </h1>
          <p className="sheet__meta">
            {order.company_name || order.contact_name} ·{' '}
            <span className="num" dir="ltr">
              {prettyPhone(order.contact_phone)}
            </span>
          </p>
        </div>
        <div className="sheet__due">
          <span className="cfg__hint">مطلوب قبل</span>
          <strong className="num" dir="ltr">
            {order.needed_by ?? '—'}
          </strong>
        </div>
      </header>

      {order.order_request_lines.map((line) => (
        <section key={line.id} className="sheet__line">
          <h2>
            <span className="num">{line.line_no}.</span> {line.product_name_ar}
            <span className="sheet__qty num"> × {formatQty(line.qty)}</span>
          </h2>

          <dl className="sheet__grid">
            {line.method_name_ar ? (
              <>
                <dt>الطريقة</dt>
                <dd>
                  {line.method_name_ar}
                  {line.colors_count && line.colors_count > 1
                    ? ` — ${line.colors_count} ألوان`
                    : ''}
                </dd>
              </>
            ) : null}

            {line.order_line_positions.length ? (
              <>
                <dt>المكان</dt>
                <dd>
                  {line.order_line_positions
                    .map((p) =>
                      p.area_w_mm
                        ? `${p.position_name_ar} — ${Number(p.area_w_mm)}×${Number(p.area_h_mm)} مم`
                        : p.position_name_ar
                    )
                    .join(' / ')}
                </dd>
              </>
            ) : null}

            {line.order_line_options.map((o) => (
              <div key={o.group_label_ar} style={{ display: 'contents' }}>
                <dt>{o.group_label_ar}</dt>
                <dd>
                  {o.item_label_ar}
                  {o.hex ? ` (${o.hex})` : ''}
                </dd>
              </div>
            ))}

            {line.order_line_assets.length ? (
              <>
                <dt>الملفات</dt>
                <dd>
                  {line.order_line_assets
                    .map((a) => a.original_name ?? a.storage_path.split('/').pop())
                    .join('، ')}
                </dd>
              </>
            ) : null}

            {line.notes ? (
              <>
                <dt>ملاحظات</dt>
                <dd>{line.notes}</dd>
              </>
            ) : null}
          </dl>

          {line.order_line_texts.length ? (
            <div className="sheet__text">
              <span className="cfg__hint">النص المطلوب طباعته — انسخه حرف بحرف</span>
              {line.order_line_texts.map((t) => (
                <p key={t.slot} className="sheet__text-line">
                  {t.content}
                  {t.font_name_ar ? (
                    <span className="sheet__font"> — {t.font_name_ar}</span>
                  ) : null}
                </p>
              ))}
            </div>
          ) : null}
        </section>
      ))}

      {order.customer_note ? (
        <section className="sheet__line">
          <h2>ملاحظات العميل</h2>
          <p>{order.customer_note}</p>
        </section>
      ) : null}

      <footer className="sheet__foot">
        <div>
          <span className="cfg__hint">راجعه</span>
          <div className="sheet__sign" />
        </div>
        <div>
          <span className="cfg__hint">نفّذه</span>
          <div className="sheet__sign" />
        </div>
        <div>
          <span className="cfg__hint">تاريخ التسليم</span>
          <div className="sheet__sign" />
        </div>
      </footer>
    </div>
  );
}
