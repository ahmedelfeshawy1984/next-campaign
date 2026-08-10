'use client';

import Link from 'next/link';
import { ORDER_STATUS_AR } from '@/lib/orders';
import { formatPrice } from '@/lib/money.js';
import { prettyPhone } from '@/lib/phone.js';

export interface OrderRow {
  id: string;
  code: string;
  contact_name: string;
  contact_phone: string;
  company_name: string | null;
  status: string;
  total: number;
  needed_by: string | null;
  created_at: string;
  price_mismatch: boolean;
}

export default function OrderTable({
  title,
  rows,
  showNeeded,
  emptyText,
}: {
  title: string;
  rows: OrderRow[];
  showNeeded?: boolean;
  emptyText: string;
}) {
  return (
    <section style={{ marginBlockStart: 26 }}>
      <h2>{title}</h2>
      {rows.length === 0 ? (
        <p className="cfg__hint">{emptyText}</p>
      ) : (
        <div className="admin__scroll">
          <table className="admin__table">
            <thead>
              <tr>
                <th>الطلب</th>
                <th>العميل</th>
                <th>الحالة</th>
                <th>الإجمالي</th>
                {showNeeded ? <th>مطلوب قبل</th> : <th>وصل</th>}
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id}>
                  <td>
                    <Link href={`/admin/requests/${r.code}`} className="num" dir="ltr">
                      {r.code}
                    </Link>
                    {r.price_mismatch ? (
                      <span className="badge badge--soft" style={{ marginInlineStart: 6 }}>
                        سعر مختلف
                      </span>
                    ) : null}
                  </td>
                  <td>
                    {r.company_name || r.contact_name}
                    <br />
                    <a
                      href={`tel:${r.contact_phone}`}
                      className="num cfg__hint"
                      dir="ltr"
                    >
                      {prettyPhone(r.contact_phone)}
                    </a>
                  </td>
                  <td>
                    <span className="chip">{ORDER_STATUS_AR[r.status] ?? r.status}</span>
                  </td>
                  <td className="num">{formatPrice(r.total)}</td>
                  <td className="num" dir="ltr">
                    {showNeeded
                      ? (r.needed_by ?? '—')
                      : new Date(r.created_at).toLocaleDateString('en-GB')}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

