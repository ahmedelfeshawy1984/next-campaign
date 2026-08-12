'use client';

import { useEffect, useState } from 'react';
import { browserSupabase } from '@/lib/supabase-browser';
import { adminErrorMessage } from '@/lib/admin';
import { isEgMobile } from '@/lib/phone.js';

type Row = Record<string, unknown>;

const TEXT_FIELDS: { key: string; label: string; dir?: 'ltr'; hint?: string }[] = [
  { key: 'tagline_ar', label: 'السطر التعريفي' },
  { key: 'whatsapp_phone', label: 'رقم الواتساب', dir: 'ltr', hint: 'من غيره زرار الواتساب مش بيظهر خالص' },
  { key: 'hotline', label: 'الخط الساخن', dir: 'ltr' },
  { key: 'email', label: 'الإيميل', dir: 'ltr' },
  { key: 'address_ar', label: 'العنوان' },
  { key: 'working_hours_ar', label: 'مواعيد العمل' },
  { key: 'quote_promise_ar', label: 'وعد الرد على العميل' },
  { key: 'rush_note_ar', label: 'ملاحظة الطلبات المستعجلة' },
  { key: 'facebook_url', label: 'فيسبوك', dir: 'ltr' },
  { key: 'instagram_url', label: 'إنستجرام', dir: 'ltr' },
];

export default function AdminSettings() {
  const sb = browserSupabase();
  const [row, setRow] = useState<Row | null | undefined>(undefined);
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null);

  function load() {
    sb.from('site_settings')
      .select('*')
      .maybeSingle()
      .then(({ data }) => setRow((data as Row) ?? null));
  }
  useEffect(load, []);

  async function patch(fields: Row) {
    setMsg(null);
    const { error } = await sb.from('site_settings').update(fields).eq('id', true);
    if (error) setMsg({ text: adminErrorMessage(error.message), bad: true });
    else {
      setRow((r) => ({ ...(r as Row), ...fields }));
      setMsg({ text: 'اتحفظ' });
    }
  }

  if (row === undefined) return <p className="empty">لحظة…</p>;
  if (!row) return <p className="empty">صف الإعدادات مش موجود — شغّل ملف التثبيت تاني.</p>;

  const wa = String(row.whatsapp_phone ?? '');

  return (
    <>
      <h1>الإعدادات</h1>
      {msg ? <p className={msg.bad ? 'notice notice--warn' : 'notice'}>{msg.text}</p> : null}

      <div className="panel">
        <div className="panel__title">الهوية</div>
        <label className="field">
          <span>اسم الشركة زي ما هيظهر في الموقع</span>
          <input
            type="text"
            defaultValue={String(row.brand_name_ar ?? '')}
            onBlur={(e) => patch({ brand_name_ar: e.target.value })}
          />
          <span className="cfg__hint">
            ده الاسم اللي بيظهر في الهيدر، وفي تبويب المتصفح، وفي نتايج جوجل.
          </span>
        </label>

        <ImageField
          label="اللوجو"
          hint="بيظهر في أعلى الموقع بدل المربع الملون. يفضّل PNG بخلفية شفافة، بعرض ٤٠٠ بكسل تقريباً."
          value={(row.logo_url ?? null) as string | null}
          folder="branding/logo"
          onSaved={(url) => patch({ logo_url: url })}
          onCleared={() => patch({ logo_url: null })}
        />

        <ImageField
          label="صورة الواجهة"
          hint="صورة كبيرة في أول الصفحة الرئيسية — يفضّل صورة حقيقية من شغلك. سيبها فاضية وهتظهر مربعات الفئات مكانها."
          value={(row.hero_url ?? null) as string | null}
          folder="branding/hero"
          onSaved={(url) => patch({ hero_url: url })}
          onCleared={() => patch({ hero_url: null })}
        />

        <label className="field">
          <span>وصف صورة الواجهة</span>
          <input
            type="text"
            defaultValue={String(row.hero_alt_ar ?? '')}
            placeholder="مثلاً: مجات وأقلام مطبوعة بلوجو شركة"
            onBlur={(e) => patch({ hero_alt_ar: e.target.value || null })}
          />
          <span className="cfg__hint">
            بيتقري لضعاف البصر، وجوجل بيقراه كمان. جملة قصيرة بتوصف اللي في الصورة.
          </span>
        </label>
      </div>

      <div className="panel">
        <div className="panel__title">التواصل</div>
        {TEXT_FIELDS.map((f) => (
          <label className="field" key={f.key}>
            <span>{f.label}</span>
            <input
              type="text"
              dir={f.dir}
              defaultValue={String(row[f.key] ?? '')}
              onBlur={(e) => patch({ [f.key]: e.target.value || null })}
            />
            {f.hint ? <span className="cfg__hint">{f.hint}</span> : null}
          </label>
        ))}
        {wa && !isEgMobile(wa) ? (
          <p className="notice notice--warn">
            رقم الواتساب ده مش رقم موبايل مصري صحيح — الزرار مش هيشتغل.
          </p>
        ) : null}
      </div>

      <div className="panel">
        <div className="panel__title">الضريبة والأسعار</div>
        <label className="field">
          <span>نسبة ضريبة القيمة المضافة</span>
          <input
            type="number"
            step="0.01"
            dir="ltr"
            defaultValue={String(Number(row.vat_rate ?? 0) * 100)}
            onBlur={(e) => patch({ vat_rate: Number(e.target.value) / 100 })}
          />
          <span className="cfg__hint">
            بالنسبة المئوية (١٤ يعني ١٤٪). بتتصوّر مع كل طلب، فتغييرها مش بيعيد كتابة
            الطلبات القديمة.
          </span>
        </label>
        <label className="check">
          <input
            type="checkbox"
            checked={!!row.prices_include_vat}
            onChange={(e) => patch({ prices_include_vat: e.target.checked })}
          />
          <span>الأسعار المعروضة شاملة الضريبة</span>
        </label>
        <label className="field">
          <span>سعر عمل ملف vector للعميل</span>
          <input
            type="number"
            dir="ltr"
            defaultValue={String(row.artwork_service_fee ?? '')}
            onBlur={(e) =>
              patch({ artwork_service_fee: e.target.value ? Number(e.target.value) : null })
            }
          />
          <span className="cfg__hint">
            بيظهر في صفحة طرق الطباعة كخدمة — أشهر شكوى في الشغل ده بتتحوّل لسطر إيراد.
          </span>
        </label>
      </div>
    </>
  );
}

/* ------------------------------------------------------------- uploader -- */

/**
 * One image, uploaded to the public product-media bucket.
 *
 * The path carries a timestamp rather than overwriting a fixed name: a CDN
 * holds a URL for a long time, and a logo replaced at the same address is a
 * logo half the visitors keep seeing for a day. A new name is a new URL and the
 * change is immediate.
 */
function ImageField({
  label,
  hint,
  value,
  folder,
  onSaved,
  onCleared,
}: {
  label: string;
  hint: string;
  value: string | null;
  folder: string;
  onSaved: (url: string) => void;
  onCleared: () => void;
}) {
  const sb = browserSupabase();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function upload(file: File) {
    setError(null);
    if (file.size > 3 * 1024 * 1024) {
      setError('الصورة أكبر من ٣ ميجا — صغّرها الأول');
      return;
    }
    setBusy(true);
    try {
      const ext = file.name.toLowerCase().split('.').pop() ?? 'png';
      const path = `${folder}-${Date.now()}.${ext}`;
      const { error: e } = await sb.storage.from('product-media').upload(path, file, {
        contentType: file.type || 'image/png',
        upsert: true,
      });
      if (e) throw new Error(e.message);
      onSaved(sb.storage.from('product-media').getPublicUrl(path).data.publicUrl);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'مشكلة في الرفع');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="field">
      <span>{label}</span>
      {value ? (
        <div className="row" style={{ marginBlockEnd: 8 }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={value}
            alt=""
            style={{
              maxInlineSize: 200,
              maxBlockSize: 90,
              objectFit: 'contain',
              background: 'var(--surface)',
              borderRadius: 8,
              padding: 6,
            }}
          />
          <button type="button" className="btn btn--ghost btn--sm" onClick={onCleared}>
            شيلها
          </button>
        </div>
      ) : null}
      <input
        type="file"
        accept="image/png,image/jpeg,image/webp,image/svg+xml"
        disabled={busy}
        onChange={(e) => e.target.files?.[0] && upload(e.target.files[0])}
      />
      <span className="cfg__hint">{hint}</span>
      {busy ? <span className="cfg__hint">بنرفع…</span> : null}
      {error ? <span className="field__error">{error}</span> : null}
    </div>
  );
}
