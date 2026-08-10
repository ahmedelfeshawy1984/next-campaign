'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { browserSupabase } from '@/lib/supabase-browser';
import { adminErrorMessage } from '@/lib/admin';
import { formatPrice, formatQty } from '@/lib/money.js';

interface Row {
  id: string;
  slug: string;
  name_ar: string;
  is_published: boolean;
  is_available: boolean;
  cover_url: string | null;
  moq: number;
  price_at_moq: number | null;
  description_ar: string | null;
  categories: { name_ar: string } | null;
  product_price_tiers: { min_qty: number }[];
  product_print_methods: { method_code: string }[];
  print_positions: { id: string }[];
}

export default function AdminProducts() {
  const router = useRouter();
  const params = useSearchParams();
  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const onlyDrafts = params.get('draft') === '1';
  const onlyNoCover = params.get('nocover') === '1';

  function load() {
    setLoading(true);
    browserSupabase()
      .from('products')
      .select(
        'id, slug, name_ar, is_published, is_available, cover_url, moq, price_at_moq, description_ar, categories(name_ar), product_price_tiers(min_qty), product_print_methods(method_code), print_positions(id)'
      )
      .order('sort_order')
      .then(({ data }) => {
        setRows((data as unknown as Row[]) ?? []);
        setLoading(false);
      });
  }
  useEffect(load, []);

  async function togglePublish(row: Row) {
    setError(null);
    const { error: e } = await browserSupabase()
      .from('products')
      .update({ is_published: !row.is_published })
      .eq('id', row.id);
    // The publish gate lives in the database, so this is where the owner finds
    // out the product is not ready — with the reason, not a silent no-op.
    if (e) setError(adminErrorMessage(e.message));
    load();
  }

  async function create() {
    const name = window.prompt('اسم المنتج الجديد؟');
    if (!name) return;
    const { data: cats } = await browserSupabase()
      .from('categories')
      .select('id')
      .order('sort_order')
      .limit(1);
    const categoryId = (cats as { id: string }[] | null)?.[0]?.id;
    if (!categoryId) {
      setError('لازم فئة واحدة على الأقل قبل ما تضيف منتج.');
      return;
    }
    const slug = `product-${Date.now()}`;
    const { data, error: e } = await browserSupabase()
      .from('products')
      .insert({ name_ar: name, slug, category_id: categoryId, moq: 1 })
      .select('id')
      .maybeSingle();
    if (e) {
      setError(adminErrorMessage(e.message));
      return;
    }
    router.push(`/admin/products/${(data as { id: string }).id}`);
  }

  const visible = rows.filter(
    (r) => (!onlyDrafts || !r.is_published) && (!onlyNoCover || !r.cover_url)
  );

  return (
    <>
      <div className="row">
        <h1 style={{ margin: 0 }}>المنتجات</h1>
        <span className="spacer" />
        <button type="button" className="btn btn--brand btn--sm" onClick={create}>
          + منتج جديد
        </button>
      </div>

      {error ? <p className="notice notice--warn">{error}</p> : null}

      <div className="chip-row" style={{ marginBlock: 14 }}>
        <Link href="/admin/products" className={`chip${!onlyDrafts && !onlyNoCover ? ' chip--on' : ''}`}>
          الكل
        </Link>
        <Link href="/admin/products?draft=1" className={`chip${onlyDrafts ? ' chip--on' : ''}`}>
          مسودات
        </Link>
        <Link href="/admin/products?nocover=1" className={`chip${onlyNoCover ? ' chip--on' : ''}`}>
          من غير صورة
        </Link>
      </div>

      {loading ? (
        <p className="empty">لحظة…</p>
      ) : (
        <div className="admin__scroll">
          <table className="admin__table">
            <thead>
              <tr>
                <th>المنتج</th>
                <th>الفئة</th>
                <th>الحد الأدنى</th>
                <th>السعر عنده</th>
                <th>جاهز؟</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {visible.map((r) => {
                // The three things the publish gate insists on, shown BEFORE
                // the owner clicks publish and gets refused.
                const missing = [
                  r.product_price_tiers.length === 0 ? 'أسعار' : null,
                  r.product_print_methods.length === 0 ? 'طريقة طباعة' : null,
                  r.print_positions.length === 0 ? 'مكان طباعة' : null,
                  !r.cover_url ? 'صورة' : null,
                  !r.description_ar ? 'وصف' : null,
                ].filter(Boolean);

                return (
                  <tr key={r.id}>
                    <td>
                      <Link href={`/admin/products/${r.id}`}>{r.name_ar}</Link>
                      <br />
                      <span className="cfg__hint num" dir="ltr">
                        {r.slug}
                      </span>
                    </td>
                    <td>{r.categories?.name_ar ?? '—'}</td>
                    <td className="num">{formatQty(r.moq)}</td>
                    <td className="num">{formatPrice(r.price_at_moq)}</td>
                    <td>
                      {missing.length ? (
                        <span className="cfg__file-warn">ناقص: {missing.join('، ')}</span>
                      ) : (
                        <span className="cfg__hint">كامل</span>
                      )}
                    </td>
                    <td>
                      <button
                        type="button"
                        className={`btn btn--sm ${r.is_published ? 'btn--ghost' : 'btn--brand'}`}
                        onClick={() => togglePublish(r)}
                      >
                        {r.is_published ? 'إخفاء' : 'نشر'}
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}
