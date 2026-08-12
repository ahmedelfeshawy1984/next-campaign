'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { clinicSupabase } from '@/lib/clinic/supabase';
import { clinicSettings } from '@/lib/clinic/visits';
import { syncCatalog, loadCatalog } from '@/lib/clinic/drugs';
import { toArabicError } from '@/lib/clinic/errors';
import type { ClinicSettings } from '@/lib/clinic/types';

// إعدادات العيادة.
//
// The print offsets are the reason this screen exists. They are millimetres of
// pre-printed letterhead the prescription must not write over, and they are
// measured against a real sheet from a real printer — which means the person
// adjusting them has the paper in their hand and needs the change to be live
// on the next print, not on the next deploy.

export default function SettingsPage() {
  const [s, setS] = useState<ClinicSettings | null | undefined>(undefined);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const [cat, setCat] = useState<{ drugs: number; syncedAt: string | null }>({
    drugs: 0, syncedAt: null,
  });

  useEffect(() => {
    clinicSettings().then(setS).catch((e) => { setError(toArabicError(e)); setS(null); });
    void loadCatalog().then((c) => setCat({ drugs: c.drugs, syncedAt: c.syncedAt }));
  }, []);

  if (s === undefined) return <p className="empty">لحظة…</p>;
  if (!s) return <p className="empty">{error ?? 'مش قادرين نقرا الإعدادات.'}</p>;

  const set = <K extends keyof ClinicSettings>(k: K, v: ClinicSettings[K]) =>
    setS({ ...s, [k]: v });

  return (
    <>
      <h1>الإعدادات</h1>

      <form
        onSubmit={async (e) => {
          e.preventDefault();
          setError(null);
          setSaved(false);
          try {
            const { error: err } = await clinicSupabase()
              .from('settings').update(s).eq('id', true);
            if (err) throw err;
            setSaved(true);
          } catch (err) {
            setError(toArabicError(err));
          }
        }}
      >
        <section className="clinic__panel">
          <h2>بيانات العيادة</h2>
          <div className="clinic__grid2">
            <label>
              <span className="cfg__hint">اسم العيادة</span>
              <input className="input" value={s.clinic_name_ar}
                onChange={(e) => set('clinic_name_ar', e.target.value)} />
            </label>
            <label>
              <span className="cfg__hint">التليفون</span>
              <input className="input num" dir="ltr" value={s.phone ?? ''}
                onChange={(e) => set('phone', e.target.value)} />
            </label>
            <label className="clinic__span2">
              <span className="cfg__hint">العنوان</span>
              <input className="input" value={s.address_ar ?? ''}
                onChange={(e) => set('address_ar', e.target.value)} />
            </label>
          </div>
        </section>

        <section className="clinic__panel">
          <h2>الطباعة</h2>
          <p className="cfg__hint">
            الروشتة بتتطبع على A5. لو ورق العيادة مطبوع فيه الترويسة، سيب
            «اطبع الترويسة» مقفول وظبّط المسافة اللي فوق بحيث الكتابة تنزل تحت
            الترويسة بالظبط.
          </p>

          <div className="clinic__grid2">
            <label>
              <span className="cfg__hint">مسافة الترويسة من فوق (مم)</span>
              <input className="input num" dir="ltr" type="number" step="0.5" min="0" max="148"
                value={Number(s.header_offset_mm)}
                onChange={(e) => set('header_offset_mm', Number(e.target.value))} />
            </label>
            <label>
              <span className="cfg__hint">المسافة من تحت (مم)</span>
              <input className="input num" dir="ltr" type="number" step="0.5" min="0" max="148"
                value={Number(s.footer_offset_mm)}
                onChange={(e) => set('footer_offset_mm', Number(e.target.value))} />
            </label>
            <label>
              <span className="cfg__hint">المسافة من الجنب (مم)</span>
              <input className="input num" dir="ltr" type="number" step="0.5" min="0" max="60"
                value={Number(s.margin_x_mm)}
                onChange={(e) => set('margin_x_mm', Number(e.target.value))} />
            </label>
            <label className="clinic__check">
              <input type="checkbox" checked={s.print_header}
                onChange={(e) => set('print_header', e.target.checked)} />
              <span>اطبع الترويسة — للورق الأبيض</span>
            </label>
          </div>

          <p className="cfg__hint">
            ⚠ ظبّطها على ورقة حقيقية: افتح أي روشتة، اطبعها على ورق العيادة،
            وقيس. مرة واحدة بس.
          </p>
        </section>

        <section className="clinic__panel">
          <h2>الأسعار</h2>
          <div className="clinic__grid2">
            <label>
              <span className="cfg__hint">سعر الكشف</span>
              <input className="input num" dir="ltr" type="number" step="0.5" min="0"
                value={Number(s.consult_fee)}
                onChange={(e) => set('consult_fee', Number(e.target.value))} />
            </label>
            <label>
              <span className="cfg__hint">سعر الإعادة</span>
              <input className="input num" dir="ltr" type="number" step="0.5" min="0"
                value={Number(s.follow_up_fee)}
                onChange={(e) => set('follow_up_fee', Number(e.target.value))} />
            </label>
            <label>
              <span className="cfg__hint">الإعادة لحد كام يوم</span>
              <input className="input num" dir="ltr" type="number" min="0"
                value={s.follow_up_days}
                onChange={(e) => set('follow_up_days', Number(e.target.value))} />
            </label>
          </div>
        </section>

        {error ? <p className="clinic__error" role="alert">{error}</p> : null}
        {saved ? <p className="clinic__ok" role="status">اتحفظت.</p> : null}

        <div className="row clinic__actions">
          <button type="submit" className="btn btn--brand">احفظ</button>
          <Link className="btn btn--ghost" href="/clinic/patients">المرضى</Link>
        </div>
      </form>

      <section className="clinic__panel">
        <h2>كتالوج الأدوية على الجهاز ده</h2>
        <p className="cfg__hint">
          {cat.drugs > 0
            ? `${cat.drugs} دوا محفوظين على الجهاز — البحث شغّال من غير نت.`
            : 'لسه ما نزلش على الجهاز ده.'}
          {cat.syncedAt
            ? ` آخر تحديث: ${new Date(cat.syncedAt).toLocaleString('ar-EG')}.`
            : ''}
        </p>
        <button
          type="button"
          className="btn btn--ghost"
          onClick={async () => {
            try {
              // Full re-pull, not a delta. This button exists for the case
              // where the local copy is suspected wrong, and a delta cannot
              // repair what it does not know is broken.
              const next = await syncCatalog(true);
              setCat({ drugs: next.drugs, syncedAt: next.syncedAt });
            } catch (e) { setError(toArabicError(e)); }
          }}
        >
          نزّل الكتالوج من الأول
        </button>
      </section>
    </>
  );
}
