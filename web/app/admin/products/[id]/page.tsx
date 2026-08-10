'use client';

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { useParams } from 'next/navigation';
import { browserSupabase } from '@/lib/supabase-browser';
import { adminErrorMessage } from '@/lib/admin';
import { formatPrice } from '@/lib/money.js';
import type { SpecDef } from '@/lib/types';

// محرر المنتج.
//
// The specs tab is GENERATED from spec_defs — scoped to the product's category
// by specs_for_category(). Adding a spec dimension is one `alter table` plus one
// row, and this screen grows the field on its own. Nothing here knows what a mug
// is.
//
// Two rules the generated form must never break:
//   * an empty number field writes NULL, never 0. Unknown is not zero, and a
//     zero-gram mug is a lie the filter will happily match.
//   * a boolean is TRI-STATE (نعم / لا / —). "Not answered" is a real answer and
//     the third option is what stops the owner having to guess.

type Row = Record<string, unknown>;
const TABS = ['أساسي', 'مواصفات', 'الأسعار', 'الطباعة', 'الخيارات', 'الصور'] as const;

export default function ProductEditor() {
  const { id } = useParams<{ id: string }>();
  const sb = browserSupabase();

  const [tab, setTab] = useState<(typeof TABS)[number]>('أساسي');
  const [product, setProduct] = useState<Row | null | undefined>(undefined);
  const [specs, setSpecs] = useState<SpecDef[]>([]);
  const [categories, setCategories] = useState<{ id: string; name_ar: string }[]>([]);
  const [methods, setMethods] = useState<{ code: string; name_ar: string; default_setup_fee: number }[]>([]);
  const [tiers, setTiers] = useState<{ id?: string; min_qty: number; unit_price: number }[]>([]);
  const [productMethods, setProductMethods] = useState<Row[]>([]);
  const [positions, setPositions] = useState<Row[]>([]);
  const [groups, setGroups] = useState<Row[]>([]);
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    const { data } = await sb.from('products').select('*').eq('id', id).maybeSingle();
    if (!data) {
      setProduct(null);
      return;
    }
    setProduct(data as Row);

    const [cats, defs, allMethods, t, pm, pos, g] = await Promise.all([
      sb.from('categories').select('id, name_ar').order('sort_order'),
      sb.rpc('specs_for_category', { p_category: (data as Row).category_id }),
      sb.from('print_methods').select('code, name_ar, default_setup_fee').order('sort_order'),
      sb.from('product_price_tiers').select('*').eq('product_id', id).order('min_qty'),
      sb.from('product_print_methods').select('*').eq('product_id', id),
      sb.from('print_positions').select('*').eq('product_id', id).order('sort_order'),
      sb
        .from('product_option_groups')
        .select('*, product_option_items(*)')
        .eq('product_id', id)
        .order('sort_order'),
    ]);

    setCategories((cats.data as { id: string; name_ar: string }[]) ?? []);
    setSpecs((defs.data as SpecDef[]) ?? []);
    setMethods((allMethods.data as typeof methods) ?? []);
    setTiers((t.data as typeof tiers) ?? []);
    setProductMethods((pm.data as Row[]) ?? []);
    setPositions((pos.data as Row[]) ?? []);
    setGroups((g.data as Row[]) ?? []);
  }, [id, sb]);

  useEffect(() => {
    load();
  }, [load]);

  async function patch(fields: Row) {
    setBusy(true);
    setMsg(null);
    const { error } = await sb.from('products').update(fields).eq('id', id);
    setBusy(false);
    if (error) setMsg({ text: adminErrorMessage(error.message), bad: true });
    else {
      setProduct((p) => ({ ...(p as Row), ...fields }));
      setMsg({ text: 'اتحفظ' });
    }
  }

  if (product === undefined) return <p className="empty">لحظة…</p>;
  if (!product) return <p className="empty">المنتج ده مش موجود.</p>;

  const p = product;
  const val = (k: string) => (p[k] ?? '') as string | number;

  return (
    <>
      <div className="row">
        <h1 style={{ margin: 0 }}>{String(p.name_ar)}</h1>
        <span className="spacer" />
        {p.is_published ? (
          <Link href={`/p/${p.slug}`} className="btn btn--ghost btn--sm" target="_blank">
            شوفه في الموقع
          </Link>
        ) : (
          <span className="chip">مسودة</span>
        )}
      </div>

      {msg ? (
        <p className={msg.bad ? 'notice notice--warn' : 'notice'}>{msg.text}</p>
      ) : null}

      <div className="chip-row" style={{ marginBlock: 14 }}>
        {TABS.map((t) => (
          <button
            key={t}
            type="button"
            className={`chip${tab === t ? ' chip--on' : ''}`}
            onClick={() => setTab(t)}
          >
            {t}
          </button>
        ))}
      </div>

      {tab === 'أساسي' ? (
        <div className="panel">
          <Field label="الاسم" value={val('name_ar')} onSave={(v) => patch({ name_ar: v })} />
          <Field
            label="الرابط (slug)"
            value={val('slug')}
            dir="ltr"
            hint="بيتغير؟ الروابط القديمة بتقع. غيّره بس لو المنتج لسه مانتشرش."
            onSave={(v) => patch({ slug: v })}
          />
          <label className="field">
            <span>الفئة</span>
            <select
              value={String(p.category_id ?? '')}
              onChange={(e) => patch({ category_id: e.target.value }).then(load)}
            >
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name_ar}
                </option>
              ))}
            </select>
          </label>
          <Field
            label="الجملة القصيرة"
            value={val('short_pitch_ar')}
            onSave={(v) => patch({ short_pitch_ar: v || null })}
          />
          <label className="field">
            <span>الوصف</span>
            <textarea
              rows={5}
              defaultValue={String(p.description_ar ?? '')}
              onBlur={(e) => patch({ description_ar: e.target.value || null })}
            />
          </label>
          <div className="row">
            <Num label="الحد الأدنى للطلب" value={p.moq} onSave={(v) => patch({ moq: v ?? 1 })} />
            <Num
              label="أقصى أماكن طباعة"
              value={p.max_positions}
              onSave={(v) => patch({ max_positions: v ?? 1 })}
            />
            <Num
              label="أقصى سطور نص"
              value={p.max_text_lines}
              onSave={(v) => patch({ max_text_lines: v ?? 0 })}
            />
          </div>
          <div className="row">
            <Num
              label="أقل مدة تنفيذ (يوم)"
              value={p.lead_days_min}
              onSave={(v) => patch({ lead_days_min: v })}
            />
            <Num
              label="أقصى مدة تنفيذ (يوم)"
              value={p.lead_days_max}
              onSave={(v) => patch({ lead_days_max: v })}
            />
          </div>
          <Check label="لعملاء الشركات" checked={!!p.for_corporate} onChange={(v) => patch({ for_corporate: v })} />
          <Check label="لهدايا الأفراد" checked={!!p.for_individual} onChange={(v) => patch({ for_individual: v })} />
          <Check label="بيقبل رفع لوجو" checked={!!p.allows_logo} onChange={(v) => patch({ allows_logo: v })} />
          <Check label="بيقبل كتابة نص" checked={!!p.allows_text} onChange={(v) => patch({ allows_text: v })} />
          <Check label="متاح حالياً" checked={!!p.is_available} onChange={(v) => patch({ is_available: v })} />
          <Check label="مميّز في الرئيسية" checked={!!p.is_featured} onChange={(v) => patch({ is_featured: v })} />
        </div>
      ) : null}

      {tab === 'مواصفات' ? (
        <div className="panel">
          <p className="cfg__hint">
            الخانات دي متولّدة من كتالوج المواصفات حسب فئة المنتج. سيب أي خانة فاضية لو
            مش عارف قيمتها — الفاضي معناه «مش معروف»، مش صفر.
          </p>
          {specs.map((d) => {
            const current = p[d.key];
            if (d.kind === 'bool') {
              return (
                <label className="field" key={d.key}>
                  <span>{d.label_ar}</span>
                  <select
                    value={current === null || current === undefined ? '' : String(current)}
                    onChange={(e) =>
                      patch({ [d.key]: e.target.value === '' ? null : e.target.value === 'true' })
                    }
                  >
                    <option value="">—</option>
                    <option value="true">نعم</option>
                    <option value="false">لا</option>
                  </select>
                </label>
              );
            }
            if (d.kind === 'number') {
              return (
                <Num
                  key={d.key}
                  label={`${d.label_ar}${d.unit_ar ? ` (${d.unit_ar})` : ''}`}
                  value={current}
                  onSave={(v) => patch({ [d.key]: v })}
                />
              );
            }
            return (
              <Field
                key={d.key}
                label={d.label_ar}
                value={(current ?? '') as string}
                onSave={(v) => patch({ [d.key]: v || null })}
              />
            );
          })}
          {specs.length === 0 ? <p className="cfg__hint">مفيش مواصفات للفئة دي.</p> : null}
        </div>
      ) : null}

      {tab === 'الأسعار' ? (
        <TiersEditor
          productId={id}
          moq={Number(p.moq)}
          tiers={tiers}
          onChanged={load}
          onError={(t) => setMsg({ text: t, bad: true })}
        />
      ) : null}

      {tab === 'الطباعة' ? (
        <PrintEditor
          productId={id}
          methods={methods}
          productMethods={productMethods}
          positions={positions}
          onChanged={load}
          onError={(t) => setMsg({ text: t, bad: true })}
        />
      ) : null}

      {tab === 'الخيارات' ? (
        <OptionsEditor productId={id} groups={groups} onChanged={load} />
      ) : null}

      {tab === 'الصور' ? (
        <CoverEditor
          productId={id}
          coverUrl={(p.cover_url ?? null) as string | null}
          onChanged={load}
          onError={(t) => setMsg({ text: t, bad: true })}
        />
      ) : null}

      {busy ? <p className="cfg__hint">بنحفظ…</p> : null}
    </>
  );
}

/* -------------------------------------------------------------- inputs -- */

function Field({
  label,
  value,
  onSave,
  dir,
  hint,
}: {
  label: string;
  value: string | number;
  onSave: (v: string) => void;
  dir?: 'ltr' | 'rtl';
  hint?: string;
}) {
  return (
    <label className="field">
      <span>{label}</span>
      <input type="text" dir={dir} defaultValue={String(value)} onBlur={(e) => onSave(e.target.value)} />
      {hint ? <span className="cfg__hint">{hint}</span> : null}
    </label>
  );
}

/** Empty writes NULL, never 0. */
function Num({
  label,
  value,
  onSave,
}: {
  label: string;
  value: unknown;
  onSave: (v: number | null) => void;
}) {
  return (
    <label className="field" style={{ flex: '1 1 140px' }}>
      <span>{label}</span>
      <input
        type="number"
        dir="ltr"
        defaultValue={value === null || value === undefined ? '' : String(value)}
        onBlur={(e) => onSave(e.target.value === '' ? null : Number(e.target.value))}
      />
    </label>
  );
}

function Check({
  label,
  checked,
  onChange,
}: {
  label: string;
  checked: boolean;
  onChange: (v: boolean) => void;
}) {
  return (
    <label className="check">
      <input type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)} />
      <span>{label}</span>
    </label>
  );
}

/* --------------------------------------------------------------- tiers -- */

function TiersEditor({
  productId,
  moq,
  tiers,
  onChanged,
  onError,
}: {
  productId: string;
  moq: number;
  tiers: { id?: string; min_qty: number; unit_price: number }[];
  onChanged: () => void;
  onError: (t: string) => void;
}) {
  const sb = browserSupabase();
  const [qty, setQty] = useState('');
  const [price, setPrice] = useState('');

  async function add() {
    const { error } = await sb
      .from('product_price_tiers')
      .insert({ product_id: productId, min_qty: Number(qty), unit_price: Number(price) });
    if (error) onError(adminErrorMessage(error.message));
    else {
      setQty('');
      setPrice('');
    }
    onChanged();
  }

  async function remove(tierId: string) {
    const { error } = await sb.from('product_price_tiers').delete().eq('id', tierId);
    if (error) onError(adminErrorMessage(error.message));
    onChanged();
  }

  const covered = tiers.some((t) => t.min_qty <= moq);

  return (
    <div className="panel">
      <p className="cfg__hint">
        سعر القطعة عند كل كمية. لازم شريحة عند الحد الأدنى (
        <span className="num">{moq}</span>) أو تحته، والسعر لازم ينزل أو يفضل ثابت كل ما
        الكمية تزيد — القاعدة بترفض غير كده.
      </p>

      {!covered && tiers.length ? (
        <p className="notice notice--warn">
          مفيش شريحة عند الحد الأدنى — المنتج مش هيتنشر كده.
        </p>
      ) : null}

      <table className="admin__table">
        <thead>
          <tr>
            <th>من كمية</th>
            <th>سعر القطعة</th>
            <th />
          </tr>
        </thead>
        <tbody>
          {tiers.map((t) => (
            <tr key={t.id}>
              <td className="num">{t.min_qty}</td>
              <td className="num">{formatPrice(t.unit_price)}</td>
              <td>
                <button
                  type="button"
                  className="cfg__file-x"
                  onClick={() => remove(t.id!)}
                  aria-label="امسح الشريحة"
                >
                  ✕
                </button>
              </td>
            </tr>
          ))}
          <tr>
            <td>
              <input
                className="cfg__text"
                type="number"
                dir="ltr"
                value={qty}
                onChange={(e) => setQty(e.target.value)}
              />
            </td>
            <td>
              <input
                className="cfg__text"
                type="number"
                dir="ltr"
                value={price}
                onChange={(e) => setPrice(e.target.value)}
              />
            </td>
            <td>
              <button
                type="button"
                className="btn btn--brand btn--sm"
                disabled={!qty || !price}
                onClick={add}
              >
                ضيف
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  );
}

/* --------------------------------------------------------------- print -- */

function PrintEditor({
  productId,
  methods,
  productMethods,
  positions,
  onChanged,
  onError,
}: {
  productId: string;
  methods: { code: string; name_ar: string; default_setup_fee: number }[];
  productMethods: Row[];
  positions: Row[];
  onChanged: () => void;
  onError: (t: string) => void;
}) {
  const sb = browserSupabase();
  const chosen = new Set(productMethods.map((m) => String(m.method_code)));

  async function toggleMethod(code: string, on: boolean) {
    const def = methods.find((m) => m.code === code);
    const { error } = on
      ? await sb.from('product_print_methods').insert({
          product_id: productId,
          method_code: code,
          // Pre-filled from the method's default so the owner only types when
          // THIS product differs.
          setup_fee: def?.default_setup_fee ?? 0,
        })
      : await sb
          .from('product_print_methods')
          .delete()
          .eq('product_id', productId)
          .eq('method_code', code);
    if (error) onError(adminErrorMessage(error.message));
    onChanged();
  }

  async function patchMethod(code: string, fields: Row) {
    const { error } = await sb
      .from('product_print_methods')
      .update(fields)
      .eq('product_id', productId)
      .eq('method_code', code);
    if (error) onError(adminErrorMessage(error.message));
    onChanged();
  }

  async function addPosition() {
    const name = window.prompt('اسم المكان؟ (زي: الوش)');
    if (!name) return;
    const { error } = await sb.from('print_positions').insert({
      product_id: productId,
      code: `pos-${Date.now()}`,
      name_ar: name,
      is_default: positions.length === 0,
    });
    if (error) onError(adminErrorMessage(error.message));
    onChanged();
  }

  return (
    <>
      <div className="panel">
        <div className="panel__title">طرق الطباعة</div>
        {methods.map((m) => {
          const row = productMethods.find((x) => x.method_code === m.code);
          return (
            <div key={m.code} style={{ borderBlockEnd: '1px solid var(--line)', paddingBlock: 10 }}>
              <label className="check" style={{ margin: 0 }}>
                <input
                  type="checkbox"
                  checked={chosen.has(m.code)}
                  onChange={(e) => toggleMethod(m.code, e.target.checked)}
                />
                <span>{m.name_ar}</span>
              </label>
              {row ? (
                <div className="row" style={{ marginBlockStart: 8 }}>
                  <Num
                    label="كليشيه"
                    value={row.setup_fee}
                    onSave={(v) => patchMethod(m.code, { setup_fee: v ?? 0 })}
                  />
                  <Num
                    label="إضافة للقطعة"
                    value={row.unit_addon}
                    onSave={(v) => patchMethod(m.code, { unit_addon: v ?? 0 })}
                  />
                  <Num
                    label="لكل لون زيادة"
                    value={row.addon_per_color}
                    onSave={(v) => patchMethod(m.code, { addon_per_color: v ?? 0 })}
                  />
                  <Num
                    label="أقصى ألوان"
                    value={row.max_colors}
                    onSave={(v) => patchMethod(m.code, { max_colors: v })}
                  />
                  <Num
                    label="حد أدنى للطريقة"
                    value={row.method_min_qty}
                    onSave={(v) => patchMethod(m.code, { method_min_qty: v })}
                  />
                  <Num
                    label="كليشيه مجاني فوق"
                    value={row.setup_fee_waived_over_qty}
                    onSave={(v) => patchMethod(m.code, { setup_fee_waived_over_qty: v })}
                  />
                  <Check
                    label="الكليشيه لكل لون"
                    checked={!!row.setup_fee_per_color}
                    onChange={(v) => patchMethod(m.code, { setup_fee_per_color: v })}
                  />
                </div>
              ) : null}
            </div>
          );
        })}
      </div>

      <div className="panel">
        <div className="row">
          <div className="panel__title" style={{ margin: 0 }}>
            أماكن الطباعة
          </div>
          <span className="spacer" />
          <button type="button" className="btn btn--brand btn--sm" onClick={addPosition}>
            + مكان
          </button>
        </div>
        {positions.map((pos) => (
          <div key={String(pos.id)} style={{ borderBlockStart: '1px solid var(--line)', paddingBlock: 10 }}>
            <div className="row">
              <strong>{String(pos.name_ar)}</strong>
              <span className="spacer" />
              <button
                type="button"
                className="cfg__file-x"
                aria-label="امسح المكان"
                onClick={async () => {
                  await sb.from('print_positions').delete().eq('id', pos.id as string);
                  onChanged();
                }}
              >
                ✕
              </button>
            </div>
            <div className="row">
              <Num
                label="عرض مساحة الطباعة (مم)"
                value={pos.area_w_mm}
                onSave={async (v) => {
                  await sb.from('print_positions').update({ area_w_mm: v }).eq('id', pos.id as string);
                  onChanged();
                }}
              />
              <Num
                label="ارتفاعها (مم)"
                value={pos.area_h_mm}
                onSave={async (v) => {
                  await sb.from('print_positions').update({ area_h_mm: v }).eq('id', pos.id as string);
                  onChanged();
                }}
              />
            </div>
            <p className="cfg__hint">
              أرقام المعاينة (نسبة % من الصورة) — سيبها فاضية لو مش عايز معاينة على الصورة.
            </p>
            <div className="row">
              {(['preview_x', 'preview_y', 'preview_w', 'preview_h'] as const).map((k) => (
                <Num
                  key={k}
                  label={k.replace('preview_', '')}
                  value={pos[k]}
                  onSave={async (v) => {
                    await sb.from('print_positions').update({ [k]: v }).eq('id', pos.id as string);
                    onChanged();
                  }}
                />
              ))}
            </div>
          </div>
        ))}
        {positions.length === 0 ? (
          <p className="cfg__hint">مفيش أماكن — المنتج مش هيتنشر من غير مكان واحد على الأقل.</p>
        ) : null}
      </div>
    </>
  );
}

/* ------------------------------------------------------------- options -- */

function OptionsEditor({
  productId,
  groups,
  onChanged,
}: {
  productId: string;
  groups: Row[];
  onChanged: () => void;
}) {
  const sb = browserSupabase();

  return (
    <div className="panel">
      <div className="row">
        <div className="panel__title" style={{ margin: 0 }}>
          مجموعات الخيارات
        </div>
        <span className="spacer" />
        <button
          type="button"
          className="btn btn--brand btn--sm"
          onClick={async () => {
            const label = window.prompt('اسم المجموعة؟ (زي: اللون)');
            if (!label) return;
            await sb.from('product_option_groups').insert({
              product_id: productId,
              code: `grp-${Date.now()}`,
              label_ar: label,
            });
            onChanged();
          }}
        >
          + مجموعة
        </button>
      </div>

      {groups.map((g) => {
        const items = (g.product_option_items as Row[]) ?? [];
        return (
          <div key={String(g.id)} style={{ borderBlockStart: '1px solid var(--line)', paddingBlock: 10 }}>
            <div className="row">
              <strong>{String(g.label_ar)}</strong>
              <span className="spacer" />
              <button
                type="button"
                className="btn btn--ghost btn--sm"
                onClick={async () => {
                  const label = window.prompt('اسم الخيار؟');
                  if (!label) return;
                  const hex = window.prompt('كود اللون (#RRGGBB) — سيبه فاضي لو مش لون');
                  const delta = window.prompt('فرق السعر للقطعة؟ (0 لو مفيش)') ?? '0';
                  await sb.from('product_option_items').insert({
                    group_id: g.id,
                    value: `opt-${Date.now()}`,
                    label_ar: label,
                    hex: hex || null,
                    price_delta: Number(delta) || 0,
                  });
                  onChanged();
                }}
              >
                + خيار
              </button>
              <button
                type="button"
                className="cfg__file-x"
                aria-label="امسح المجموعة"
                onClick={async () => {
                  await sb.from('product_option_groups').delete().eq('id', g.id as string);
                  onChanged();
                }}
              >
                ✕
              </button>
            </div>
            <div className="chip-row" style={{ marginBlockStart: 8 }}>
              {items.map((i) => (
                <span key={String(i.id)} className="chip">
                  {i.hex ? (
                    <span
                      className="swatch"
                      style={{ background: String(i.hex), inlineSize: 14, blockSize: 14 }}
                    />
                  ) : null}
                  {String(i.label_ar)}
                  {Number(i.price_delta) > 0 ? (
                    <span className="num">+{formatPrice(i.price_delta as number)}</span>
                  ) : null}
                  <button
                    type="button"
                    className="cfg__file-x"
                    style={{ inlineSize: 18, blockSize: 18 }}
                    aria-label="امسح"
                    onClick={async () => {
                      await sb.from('product_option_items').delete().eq('id', i.id as string);
                      onChanged();
                    }}
                  >
                    ✕
                  </button>
                </span>
              ))}
            </div>
          </div>
        );
      })}
      {groups.length === 0 ? <p className="cfg__hint">مفيش خيارات — وده عادي جداً.</p> : null}
    </div>
  );
}

/* --------------------------------------------------------------- cover -- */

function CoverEditor({
  productId,
  coverUrl,
  onChanged,
  onError,
}: {
  productId: string;
  coverUrl: string | null;
  onChanged: () => void;
  onError: (t: string) => void;
}) {
  const sb = browserSupabase();
  const [busy, setBusy] = useState(false);

  async function upload(file: File) {
    setBusy(true);
    try {
      const ext = file.name.toLowerCase().split('.').pop() ?? 'jpg';
      const path = `${productId}/cover-${Date.now()}.${ext}`;
      const { error } = await sb.storage.from('product-media').upload(path, file, {
        contentType: file.type || 'image/jpeg',
        upsert: true,
      });
      if (error) throw new Error(error.message);
      const { data } = sb.storage.from('product-media').getPublicUrl(path);
      await sb.from('products').update({ cover_url: data.publicUrl }).eq('id', productId);
      onChanged();
    } catch (e) {
      onError(e instanceof Error ? e.message : 'مشكلة في رفع الصورة');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="panel">
      <div className="panel__title">صورة الغلاف</div>
      <p className="cfg__hint">
        الصورة دي هي اللي بتظهر في معاينة الواتساب لما حد يبعت لينك المنتج. من غيرها
        اللينك بيطلع مربع رمادي.
      </p>
      {coverUrl ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={coverUrl}
          alt=""
          style={{ maxInlineSize: 260, borderRadius: 10, marginBlock: 10 }}
        />
      ) : null}
      <input
        type="file"
        accept="image/png,image/jpeg,image/webp"
        disabled={busy}
        onChange={(e) => e.target.files?.[0] && upload(e.target.files[0])}
      />
      {busy ? <p className="cfg__hint">بنرفع…</p> : null}
    </div>
  );
}
