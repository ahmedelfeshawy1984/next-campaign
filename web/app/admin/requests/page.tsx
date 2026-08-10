'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
import { browserSupabase } from '@/lib/supabase-browser';
import { ORDER_STATUS_AR } from '@/lib/orders';
import { formatPrice } from '@/lib/money.js';
import { prettyPhone } from '@/lib/phone.js';

interface Row {
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
  whatsapp_sent_at: string | null;
}

const STATUSES = Object.keys(ORDER_STATUS_AR);

export default function RequestsPage() {
  const params = useSearchParams();
  const [status, setStatus] = useState<string>(params.get('status') ?? '');
  const [q, setQ] = useState('');
  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    setLoading(true);
    let query = browserSupabase()
      .from('order_requests')
      .select(
        'id, code, contact_name, contact_phone, company_name, status, total, needed_by, created_at, price_mismatch, whatsapp_sent_at'
      )
      .order('created_at', { ascending: false })
      .limit(200);

    if (status) query = query.eq('status', status);
    // Phone first: it is what the customer says on the call, and it is the one
    // field that is already normalised so a match is exact.
    const term = q.trim();
    if (term) {
      const digits = term.replace(/[^0-9]/g, '');
      query = digits
        ? query.ilike('contact_phone', `%${digits}%`)
        : query.or(`contact_name.ilike.%${term}%,company_name.ilike.%${term}%,code.ilike.%${term}%`);
    }

    query.then(({ data }) => {
      setRows((data as Row[]) ?? []);
      setLoading(false);
    });
  }, [status, q]);

  return (
    <>
      <h1>الطلبات</h1>

      <div className="row" style={{ marginBlockEnd: 14 }}>
        <input
          className="cfg__text"
          style={{ maxInlineSize: 260 }}
          placeholder="موبايل أو اسم أو رقم طلب"
          value={q}
          onChange={(e) => setQ(e.target.value)}
        />
        <span className="chip-row">
          <button
            type="button"
            className={`chip${status === '' ? ' chip--on' : ''}`}
            onClick={() => setStatus('')}
          >
            الكل
          </button>
          {STATUSES.map((s) => (
            <button
              key={s}
              type="button"
              className={`chip${status === s ? ' chip--on' : ''}`}
              onClick={() => setStatus(s)}
            >
              {ORDER_STATUS_AR[s]}
            </button>
          ))}
        </span>
      </div>

      {loading ? (
        <p className="empty">لحظة…</p>
      ) : rows.length === 0 ? (
        <p className="empty">مفيش طلبات بالفلاتر دي.</p>
      ) : (
        <div className="admin__scroll">
          <table className="admin__table">
            <thead>
              <tr>
                <th>الطلب</th>
                <th>العميل</th>
                <th>الحالة</th>
                <th>الإجمالي</th>
                <th>مطلوب قبل</th>
                <th>وصل</th>
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
                    {!r.whatsapp_sent_at ? (
                      // Filled the form and never opened the chat: a different
                      // follow-up from somebody who messaged and got no reply.
                      <span className="badge badge--muted" style={{ marginInlineStart: 6 }}>
                        مفتحش واتساب
                      </span>
                    ) : null}
                  </td>
                  <td>
                    {r.company_name || r.contact_name}
                    <br />
                    <a href={`tel:${r.contact_phone}`} className="num cfg__hint" dir="ltr">
                      {prettyPhone(r.contact_phone)}
                    </a>
                  </td>
                  <td>
                    <span className="chip">{ORDER_STATUS_AR[r.status] ?? r.status}</span>
                  </td>
                  <td className="num">{formatPrice(r.total)}</td>
                  <td className="num" dir="ltr">
                    {r.needed_by ?? '—'}
                  </td>
                  <td className="num" dir="ltr">
                    {new Date(r.created_at).toLocaleDateString('en-GB')}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}
