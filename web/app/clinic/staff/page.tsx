'use client';

import { useCallback, useEffect, useState } from 'react';
import { clinicSupabase } from '@/lib/clinic/supabase';
import { toArabicError } from '@/lib/clinic/errors';
import { ROLE_LABEL } from '@/lib/clinic/session';
import { prettyPhone } from '@/lib/phone.js';
import type { ClinicStaff, StaffRole } from '@/lib/clinic/types';

// فريق العيادة — دكاترة واستقبال.
//
// The rx_prefix column is the one that looks decorative and is not: it is the
// first segment of every prescription number that doctor's device generates
// offline, and it is what keeps two doctors' local counters from colliding.
// It is shown, and it is not editable after the fact — changing it would
// orphan the numbering of everything already printed.

export default function StaffPage() {
  const [rows, setRows] = useState<ClinicStaff[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [adding, setAdding] = useState(false);

  // async/await rather than .then().catch(): PostgREST's builder is a
  // thenable, not a Promise, so it has no .catch() to chain onto.
  const load = useCallback(async () => {
    try {
      const { data, error: e } = await clinicSupabase().rpc('staff_list');
      if (e) throw e;
      setRows((data ?? []) as ClinicStaff[]);
      setError(null);
    } catch (e) {
      setError(toArabicError(e));
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  return (
    <>
      <div className="row clinic__head">
        <h1>الفريق</h1>
        <span className="spacer" />
        <button type="button" className="btn btn--brand" onClick={() => setAdding(!adding)}>
          + حساب جديد
        </button>
      </div>

      {error ? <p className="clinic__warn">{error}</p> : null}

      {adding ? (
        <NewStaff onDone={() => { setAdding(false); void load(); }} onError={setError} />
      ) : null}

      <table className="clinic__table">
        <thead>
          <tr>
            <th>الاسم</th>
            <th>الدور</th>
            <th>الموبايل</th>
            <th>بادئة الروشتة</th>
            <th>الحالة</th>
            <th />
          </tr>
        </thead>
        <tbody>
          {rows.map((s) => (
            <tr key={s.id} className={s.is_active ? undefined : 'is-off'}>
              <td>
                <strong>{s.display_name}</strong>
                {s.specialty_ar ? <><br /><span className="cfg__hint">{s.specialty_ar}</span></> : null}
              </td>
              <td>{ROLE_LABEL[s.role]}</td>
              <td className="num" dir="ltr">{s.phone ? prettyPhone(s.phone) : '—'}</td>
              <td className="num" dir="ltr">{s.rx_prefix ?? '—'}</td>
              <td>{s.is_active ? 'شغّال' : 'موقوف'}</td>
              <td>
                <button
                  className="btn btn--ghost btn--sm"
                  onClick={async () => {
                    try {
                      const { error: e } = await clinicSupabase().rpc('set_staff_active', {
                        p_id: s.id, p_active: !s.is_active,
                      });
                      if (e) throw e;
                      await load();
                    } catch (e) { setError(toArabicError(e)); }
                  }}
                >
                  {s.is_active ? 'وقّفه' : 'رجّعه'}
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </>
  );
}

function NewStaff({ onDone, onError }: { onDone: () => void; onError: (m: string) => void }) {
  const [f, setF] = useState({
    phone: '', full_name: '', password: '', role: 'doctor' as StaffRole,
    display_name: '', title_ar: '', specialty_ar: '', syndicate_no: '',
  });
  const [busy, setBusy] = useState(false);

  return (
    <form
      className="clinic__panel"
      onSubmit={async (e) => {
        e.preventDefault();
        setBusy(true);
        try {
          const { error } = await clinicSupabase().rpc('create_staff', {
            p_phone: f.phone,
            p_full_name: f.full_name,
            p_password: f.password,
            p_role: f.role,
            p_display_name: f.display_name || null,
            p_title_ar: f.title_ar || null,
            p_specialty_ar: f.specialty_ar || null,
            p_syndicate_no: f.syndicate_no || null,
            p_rx_prefix: null,      // generated server-side, and unique
          });
          if (error) throw error;
          onDone();
        } catch (err) {
          onError(toArabicError(err));
        } finally {
          setBusy(false);
        }
      }}
    >
      <h2>حساب جديد</h2>
      <div className="clinic__grid2">
        <label>
          <span className="cfg__hint">الاسم</span>
          <input className="input" required value={f.full_name}
            onChange={(e) => setF({ ...f, full_name: e.target.value })} />
        </label>
        <label>
          <span className="cfg__hint">الموبايل — ده اسم الدخول</span>
          <input className="input num" dir="ltr" inputMode="tel" required value={f.phone}
            onChange={(e) => setF({ ...f, phone: e.target.value })} />
        </label>
        <label>
          <span className="cfg__hint">كلمة السر</span>
          <input className="input" type="text" required minLength={6} value={f.password}
            onChange={(e) => setF({ ...f, password: e.target.value })} />
        </label>
        <label>
          <span className="cfg__hint">الدور</span>
          <select className="input" value={f.role}
            onChange={(e) => setF({ ...f, role: e.target.value as StaffRole })}>
            <option value="doctor">دكتور</option>
            <option value="reception">استقبال</option>
            <option value="director">ديريكتور</option>
          </select>
        </label>

        {f.role !== 'reception' ? (
          <>
            <label>
              <span className="cfg__hint">الاسم زي ما بيتطبع على الروشتة</span>
              <input className="input" placeholder="د. أحمد الفشاوي" value={f.display_name}
                onChange={(e) => setF({ ...f, display_name: e.target.value })} />
            </label>
            <label>
              <span className="cfg__hint">اللقب</span>
              <input className="input" placeholder="استشاري" value={f.title_ar}
                onChange={(e) => setF({ ...f, title_ar: e.target.value })} />
            </label>
            <label>
              <span className="cfg__hint">التخصص</span>
              <input className="input" placeholder="باطنة وسكر" value={f.specialty_ar}
                onChange={(e) => setF({ ...f, specialty_ar: e.target.value })} />
            </label>
            <label>
              <span className="cfg__hint">رقم النقابة</span>
              <input className="input num" dir="ltr" value={f.syndicate_no}
                onChange={(e) => setF({ ...f, syndicate_no: e.target.value })} />
            </label>
          </>
        ) : null}
      </div>

      <div className="row">
        <button type="submit" className="btn btn--brand" disabled={busy}>
          {busy ? 'لحظة…' : 'اعمل الحساب'}
        </button>
        <span className="cfg__hint">
          بادئة رقم الروشتة بتتولّد لوحدها وما بتتغيّرش بعد كده.
        </span>
      </div>
    </form>
  );
}
