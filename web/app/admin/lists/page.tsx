'use client';

import { useCallback, useEffect, useState } from 'react';
import { browserSupabase } from '@/lib/supabase-browser';
import { adminErrorMessage } from '@/lib/admin';

type Row = Record<string, unknown>;

// الفئات والمناسبات والخطوط في شاشة واحدة.
//
// Three tables that are edited twice a year each. Three separate screens would
// mean three navigation items the owner scrolls past every day to reach the one
// screen he actually uses. One tabbed page, and the daily nav stays short.

const TABLES = [
  { key: 'categories', label: 'الفئات', slug: true },
  { key: 'occasions', label: 'المناسبات', slug: true },
  { key: 'print_methods', label: 'طرق الطباعة', slug: false },
  { key: 'fonts', label: 'الخطوط', slug: false },
] as const;

export default function AdminLists() {
  const sb = browserSupabase();
  const [tab, setTab] = useState<(typeof TABLES)[number]>(TABLES[0]);
  const [rows, setRows] = useState<Row[]>([]);
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null);

  const load = useCallback(() => {
    sb.from(tab.key)
      .select('*')
      .order('sort_order')
      .then(({ data }) => setRows((data as Row[]) ?? []));
  }, [sb, tab]);

  useEffect(load, [load]);

  async function patch(row: Row, fields: Row) {
    setMsg(null);
    const idField = tab.key === 'print_methods' ? 'code' : tab.key === 'fonts' ? 'key' : 'id';
    const { error } = await sb.from(tab.key).update(fields).eq(idField, row[idField]);
    if (error) setMsg({ text: adminErrorMessage(error.message), bad: true });
    else setMsg({ text: 'اتحفظ' });
    load();
  }

  async function add() {
    const name = window.prompt(`اسم ${tab.label.replace('ال', '')} الجديد؟`);
    if (!name) return;
    const stamp = Date.now();

    const payload: Row =
      tab.key === 'print_methods'
        ? { code: `m-${stamp}`, name_ar: name, color_model: 'full_color' }
        : tab.key === 'fonts'
          ? { key: `f-${stamp}`, name_ar: name, css_family: name }
          : { slug: `s-${stamp}`, name_ar: name };

    const { error } = await sb.from(tab.key).insert(payload);
    if (error) setMsg({ text: adminErrorMessage(error.message), bad: true });
    load();
  }

  return (
    <>
      <div className="row">
        <h1 style={{ margin: 0 }}>الفئات والمناسبات</h1>
        <span className="spacer" />
        <button type="button" className="btn btn--brand btn--sm" onClick={add}>
          + جديد
        </button>
      </div>

      <div className="chip-row" style={{ marginBlock: 14 }}>
        {TABLES.map((t) => (
          <button
            key={t.key}
            type="button"
            className={`chip${tab.key === t.key ? ' chip--on' : ''}`}
            onClick={() => setTab(t)}
          >
            {t.label}
          </button>
        ))}
      </div>

      {msg ? <p className={msg.bad ? 'notice notice--warn' : 'notice'}>{msg.text}</p> : null}

      <div className="panel">
        {rows.map((row, i) => (
          <div
            key={String(row.id ?? row.code ?? row.key ?? i)}
            style={{ borderBlockEnd: '1px solid var(--line)', paddingBlock: 10 }}
          >
            <div className="row">
              <input
                className="cfg__text"
                style={{ maxInlineSize: 220 }}
                defaultValue={String(row.name_ar ?? '')}
                onBlur={(e) => patch(row, { name_ar: e.target.value })}
              />
              {tab.slug ? (
                <input
                  className="cfg__text"
                  style={{ maxInlineSize: 160 }}
                  dir="ltr"
                  defaultValue={String(row.slug ?? '')}
                  onBlur={(e) => patch(row, { slug: e.target.value })}
                />
              ) : null}
              <input
                className="cfg__text"
                style={{ maxInlineSize: 90 }}
                type="number"
                dir="ltr"
                defaultValue={String(row.sort_order ?? 0)}
                onBlur={(e) => patch(row, { sort_order: Number(e.target.value) })}
              />
              <label className="check" style={{ margin: 0 }}>
                <input
                  type="checkbox"
                  checked={row.is_active !== false}
                  onChange={(e) => patch(row, { is_active: e.target.checked })}
                />
                <span>ظاهر</span>
              </label>
            </div>
            {'blurb_ar' in row ? (
              <input
                className="cfg__text"
                style={{ marginBlockStart: 6 }}
                placeholder="سطر تعريفي"
                defaultValue={String(row.blurb_ar ?? '')}
                onBlur={(e) => patch(row, { blurb_ar: e.target.value || null })}
              />
            ) : null}
          </div>
        ))}
      </div>

      <p className="cfg__hint">
        المسح مش متاح من هنا عن قصد: فئة عليها منتجات أو مناسبة مربوطة بطلبات قديمة
        بتكسر روابط موجودة. شيل علامة «ظاهر» بدل ما تمسح.
      </p>
    </>
  );
}
