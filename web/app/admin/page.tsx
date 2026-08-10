'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { browserSupabase } from '@/lib/supabase-browser';
import { dashboardCounts, type DashboardCounts } from '@/lib/admin';
import { ORDER_STATUS_AR } from '@/lib/orders';
import { formatPrice, formatQty } from '@/lib/money.js';
import { prettyPhone } from '@/lib/phone.js';
import OrderTable, { type OrderRow } from '@/components/admin/OrderTable';


// لوحة النهارده.
//
// Three questions, in the order the owner actually asks them when he opens the
// laptop: what came in overnight, what is waiting on ME, and what is about to
// be late. Everything else is a click away and does not belong on this screen.

export default function AdminHome() {
  const [counts, setCounts] = useState<DashboardCounts | null>(null);
  const [urgent, setUrgent] = useState<OrderRow[]>([]);
  const [fresh, setFresh] = useState<OrderRow[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const sb = browserSupabase();
    const cols =
      'id, code, contact_name, contact_phone, company_name, status, total, needed_by, created_at, price_mismatch';

    Promise.all([
      dashboardCounts(),
      sb
        .from('order_requests')
        .select(cols)
        .not('needed_by', 'is', null)
        .not('status', 'in', '("delivered","cancelled")')
        .order('needed_by')
        .limit(8),
      sb
        .from('order_requests')
        .select(cols)
        .in('status', ['new', 'artwork_review'])
        .order('created_at', { ascending: false })
        .limit(10),
    ])
      .then(([c, u, f]) => {
        setCounts(c);
        setUrgent((u.data as OrderRow[]) ?? []);
        setFresh((f.data as OrderRow[]) ?? []);
      })
      .finally(() => setLoading(false));
  }, []);

  if (loading) return <p className="empty">لحظة…</p>;

  const tiles: { label: string; value: number; href: string; warn?: boolean }[] = [
    { label: 'طلبات جديدة', value: counts?.new ?? 0, href: '/admin/requests?status=new' },
    {
      label: 'مستنية معاينة',
      value: counts?.awaiting_proof ?? 0,
      href: '/admin/requests?status=artwork_review',
    },
    {
      label: 'تحت التنفيذ',
      value: counts?.in_production ?? 0,
      href: '/admin/requests?status=in_production',
    },
    { label: 'قرب ميعادها', value: counts?.urgent ?? 0, href: '/admin/requests', warn: true },
    { label: 'منتجات مسودة', value: counts?.drafts ?? 0, href: '/admin/products?draft=1' },
    {
      label: 'منتجات من غير صورة',
      value: counts?.no_cover ?? 0,
      href: '/admin/products?nocover=1',
      warn: true,
    },
  ];

  return (
    <>
      <h1>اليوم</h1>

      <div className="grid" style={{ gridTemplateColumns: 'repeat(auto-fit,minmax(150px,1fr))' }}>
        {tiles.map((t) => (
          <Link key={t.label} href={t.href} className="tile admin__tile">
            <span className="admin__tile-value num">{formatQty(t.value)}</span>
            <span className="tile__blurb">{t.label}</span>
          </Link>
        ))}
      </div>

      {counts?.mismatch ? (
        <p className="notice notice--warn" style={{ marginBlockStart: 16 }}>
          <span className="num">{counts.mismatch}</span> طلب الإجمالي اللي شافه العميل
          مختلف عن حسبتنا — راجعهم قبل ما تكلمه.
        </p>
      ) : null}

      <OrderTable title="قرب ميعادها" rows={urgent} showNeeded emptyText="مفيش مواعيد قريبة." />
      <OrderTable title="جديدة ومستنية معاينة" rows={fresh} emptyText="مفيش طلبات جديدة." />
    </>
  );
}
