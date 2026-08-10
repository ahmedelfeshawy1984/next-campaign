'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { getLastOrder, type LastOrder } from '@/lib/basket';
import { markWhatsappSent } from '@/lib/orders';
import { buildOrderMessage, whatsappLink } from '@/lib/whatsapp';
import { formatPrice } from '@/lib/money.js';
import { prettyPhone } from '@/lib/phone.js';

// The confirmation.
//
// The order is ALREADY SAVED by the time this renders — with its artwork, its
// snapshots and its code. WhatsApp is a handoff, not the record. That is the
// whole difference from the static sibling site, where the message WAS the
// order and the logo was an attachment somebody had to find again three weeks
// later.
//
// The details come from localStorage rather than the URL: a code in a URL that
// anyone can visit either shows somebody else's order or shows nothing, and
// both are worse than reading back what this device just did.

export default function OrderSent({
  whatsappPhone,
  currency,
}: {
  whatsappPhone: string | null;
  currency: string;
}) {
  const [order, setOrder] = useState<LastOrder | null | undefined>(undefined);

  useEffect(() => {
    setOrder(getLastOrder());
  }, []);

  if (order === undefined) return <p className="empty">لحظة…</p>;

  if (!order) {
    return (
      <div className="empty">
        <h2>مفيش طلب على الجهاز ده</h2>
        <p>لو بعتّ طلب قبل كده من جهاز تاني، تقدر تتابعه من صفحة التتبع.</p>
        <div className="row" style={{ justifyContent: 'center', marginBlockStart: 16 }}>
          <Link href="/track" className="btn btn--ghost">
            تتبع طلب
          </Link>
          <Link href="/corporate" className="btn btn--brand">
            ابدأ طلب جديد
          </Link>
        </div>
      </div>
    );
  }

  const message = buildOrderMessage({
    code: order.code,
    contactName: '',
    phone: prettyPhone(order.phone),
    lines: [],
    subtotal: '',
    setup: '',
    vat: null,
    total: formatPrice(order.total, currency),
  });
  const wa = whatsappLink(whatsappPhone, message);

  return (
    <div className="sent">
      <p className="sent__tick">✓</p>
      <h1>وصلنا طلبك</h1>

      <p className="sent__code num" dir="ltr">
        {order.code}
      </p>
      <p className="lead" style={{ marginInline: 'auto' }}>
        احتفظ بالرقم ده — بنستخدمه في أي مراسلة عن الطلب.
        الإجمالي <span className="num">{formatPrice(order.total, currency)}</span>.
      </p>

      {wa ? (
        <a
          className="btn btn--brand"
          href={wa}
          target="_blank"
          rel="noopener noreferrer"
          onClick={() => markWhatsappSent(order.id, order.phone)}
        >
          كمّل على واتساب
        </a>
      ) : (
        <p className="notice">
          رقم الواتساب مش متسجّل في الإعدادات لسه — الطلب اتسجّل عندنا برضه
          وهنكلمك.
        </p>
      )}

      <p className="cfg__hint" style={{ marginBlockStart: 16 }}>
        ملفات التصميم اللي رفعتها محفوظة مع الطلب. هنراجعها ونبعتلك معاينة
        نهائية قبل التنفيذ.
      </p>

      <div className="row" style={{ justifyContent: 'center', marginBlockStart: 20 }}>
        <Link href="/track" className="btn btn--ghost btn--sm">
          تتبع الطلب
        </Link>
        <Link href="/corporate" className="btn btn--ghost btn--sm">
          اطلب حاجة تانية
        </Link>
      </div>
    </div>
  );
}
