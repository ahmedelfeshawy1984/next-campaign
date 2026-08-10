'use client';

import { useEffect, useState } from 'react';
import { browserSupabase } from '@/lib/supabase-browser';
import { adminErrorMessage } from '@/lib/admin';
import { isEgMobile } from '@/lib/phone.js';

type Row = Record<string, unknown>;

const TEXT_FIELDS: { key: string; label: string; dir?: 'ltr'; hint?: string }[] = [
  { key: 'brand_name_ar', label: 'اسم الشركة' },
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
