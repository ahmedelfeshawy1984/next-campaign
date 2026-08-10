'use client';

import { useEffect, useState } from 'react';
import { getLastOrder } from '@/lib/basket';
import { trackOrder, ORDER_STATUS_AR, type TrackedOrder } from '@/lib/orders';
import { formatPrice, formatQty } from '@/lib/money.js';
import { isEgMobile } from '@/lib/phone.js';

// تتبع الطلب من غير حساب.
//
// order_status() needs BOTH the id and the matching phone. The id is on this
// device from when the order was placed; the phone is what the customer knows.
// Either alone would be a way into somebody else's order — ids leak through
// browser history and shared links, and phone numbers are guessable.

export default function TrackForm({ currency }: { currency: string }) {
  const [id, setId] = useState('');
  const [phone, setPhone] = useState('');
  const [order, setOrder] = useState<TrackedOrder | null>(null);
  const [searched, setSearched] = useState(false);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    const last = getLastOrder();
    if (last) {
      setId(last.id);
      setPhone(last.phone);
    }
  }, []);

  async function look() {
    setBusy(true);
    setSearched(false);
    try {
      setOrder(await trackOrder(id.trim(), phone.trim()));
    } catch {
      setOrder(null);
    } finally {
      setSearched(true);
      setBusy(false);
    }
  }

  const steps = [
    'new',
    'contacted',
    'quoted',
    'artwork_review',
    'artwork_approved',
    'in_production',
    'ready',
    'delivered',
  ];
  const reached = order ? steps.indexOf(order.status) : -1;

  return (
    <div style={{ maxInlineSize: 620 }}>
      <div className="panel">
        <label className="field">
          <span>رقم الطلب الداخلي</span>
          <input
            type="text"
            dir="ltr"
            value={id}
            placeholder="بيتحفظ تلقائياً لو طلبت من الجهاز ده"
            onChange={(e) => setId(e.target.value)}
          />
        </label>
        <label className="field">
          <span>الموبايل اللي طلبت بيه</span>
          <input
            type="tel"
            dir="ltr"
            inputMode="numeric"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
          />
        </label>
        <button
          type="button"
          className="btn btn--brand"
          disabled={busy || !id.trim() || !isEgMobile(phone)}
          onClick={look}
        >
          {busy ? 'بندوّر…' : 'اعرض الحالة'}
        </button>
      </div>

      {searched && !order ? (
        <p className="notice notice--warn" style={{ marginBlockStart: 16 }}>
          مفيش طلب بالبيانات دي. اتأكد من الرقم والموبايل، أو كلمنا على واتساب
          ومعاك رقم الطلب.
        </p>
      ) : null}

      {order ? (
        <div className="panel" style={{ marginBlockStart: 16 }}>
          <div className="row">
            <strong className="num" dir="ltr" style={{ fontSize: '1.2rem' }}>
              {order.code}
            </strong>
            <span className="spacer" />
            <span className="badge">{ORDER_STATUS_AR[order.status] ?? order.status}</span>
          </div>

          {order.status !== 'cancelled' ? (
            <ol className="track">
              {steps.map((s, i) => (
                <li key={s} className={i <= reached ? 'track__on' : undefined}>
                  {ORDER_STATUS_AR[s]}
                </li>
              ))}
            </ol>
          ) : null}

          <table className="specs" style={{ marginBlockStart: 12 }}>
            <tbody>
              {order.lines.map((l, i) => (
                <tr key={i}>
                  <th scope="row">
                    {l.product_name_ar}
                    {l.method_name_ar ? ` — ${l.method_name_ar}` : ''}
                  </th>
                  <td className="num">
                    {formatQty(l.qty)} × {formatPrice(l.line_total / l.qty, currency)}
                  </td>
                </tr>
              ))}
              <tr>
                <th scope="row">الإجمالي</th>
                <td className="num">{formatPrice(order.total, currency)}</td>
              </tr>
              {order.needed_by ? (
                <tr>
                  <th scope="row">مطلوب قبل</th>
                  <td className="num" dir="ltr">
                    {order.needed_by}
                  </td>
                </tr>
              ) : null}
            </tbody>
          </table>
        </div>
      ) : null}
    </div>
  );
}
