'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { searchPatients, savePatient, ageLabel } from '@/lib/clinic/patients';
import { currentStaff, canExamine } from '@/lib/clinic/session';
import { toArabicError } from '@/lib/clinic/errors';
import { prettyPhone } from '@/lib/phone.js';
import type { PatientSearchRow, ClinicStaff } from '@/lib/clinic/types';

export default function PatientsPage() {
  const [staff, setStaff] = useState<ClinicStaff | null>(null);
  const [term, setTerm] = useState('');
  const [rows, setRows] = useState<PatientSearchRow[]>([]);
  const [adding, setAdding] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    void currentStaff().then(setStaff);
  }, []);

  useEffect(() => {
    // Debounced HERE and not in DrugPicker, and the difference is the point:
    // this one may cross the network, the drug search never does.
    const t = window.setTimeout(() => {
      searchPatients(term).then(setRows).catch((e) => setError(toArabicError(e)));
    }, 250);
    return () => window.clearTimeout(t);
  }, [term]);

  return (
    <>
      <div className="row clinic__head">
        <h1>المرضى</h1>
        <span className="spacer" />
        <button type="button" className="btn btn--brand" onClick={() => setAdding(true)}>
          + مريض جديد
        </button>
      </div>

      <input
        className="input"
        placeholder="ابحث بالاسم أو الموبايل أو رقم الملف…"
        value={term}
        onChange={(e) => setTerm(e.target.value)}
        autoFocus
      />

      {error ? <p className="clinic__warn">{error}</p> : null}

      {adding ? (
        <NewPatient
          onDone={(id) => {
            setAdding(false);
            setTerm('');
            void searchPatients('').then(setRows);
            if (id && canExamine(staff)) window.location.assign(`/clinic/visit/${id}`);
          }}
          onCancel={() => setAdding(false)}
        />
      ) : null}

      {rows.length === 0 ? (
        <p className="empty">{term ? 'مفيش مريض بالاسم ده.' : 'اكتب حاجة عشان تدوّر.'}</p>
      ) : (
        <ul className="clinic__patients">
          {rows.map((p) => (
            <li key={p.id}>
              <div>
                <strong>{p.full_name}</strong>
                <span className="cfg__hint">
                  {p.file_no
                    ? <span className="num" dir="ltr">ملف {p.file_no}</span>
                    : <em>لسه ما اترفعش</em>}
                  {p.phone ? <> · <span className="num" dir="ltr">{prettyPhone(p.phone)}</span></> : null}
                  {p.birth_date ? ` · ${ageLabel(p.birth_date)}` : ''}
                </span>
                {/* Allergies ride along on the SEARCH row, before anyone has
                    opened anything. It is the one fact that must never need a
                    second click. */}
                {p.allergies_ar ? (
                  <span className="clinic__allergy-chip">حساسية: {p.allergies_ar}</span>
                ) : null}
              </div>

              <div className="row">
                <Link className="btn btn--ghost btn--sm" href={`/clinic/patients/${p.id}`}>
                  الملف
                </Link>
                {canExamine(staff) ? (
                  <Link className="btn btn--brand btn--sm" href={`/clinic/visit/${p.id}`}>
                    كشف
                  </Link>
                ) : null}
              </div>
            </li>
          ))}
        </ul>
      )}
    </>
  );
}

function NewPatient({
  onDone,
  onCancel,
}: {
  onDone: (id: string | null) => void;
  onCancel: () => void;
}) {
  const [form, setForm] = useState({
    full_name: '', phone: '', gender: '', birth_date: '',
    allergies_ar: '', chronic_ar: '',
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  return (
    <form
      className="clinic__panel"
      onSubmit={async (e) => {
        e.preventDefault();
        setBusy(true);
        setError(null);
        try {
          const p = await savePatient({
            full_name: form.full_name,
            phone: form.phone || null,
            gender: (form.gender || null) as 'male' | 'female' | null,
            birth_date: form.birth_date || null,
            allergies_ar: form.allergies_ar || null,
            chronic_ar: form.chronic_ar || null,
          });
          onDone(p.id);
        } catch (err) {
          setError(toArabicError(err));
          setBusy(false);
        }
      }}
    >
      <h2>مريض جديد</h2>

      <div className="clinic__grid2">
        <label>
          <span className="cfg__hint">الاسم</span>
          <input
            className="input" required autoFocus
            value={form.full_name}
            onChange={(e) => setForm({ ...form, full_name: e.target.value })}
          />
        </label>
        <label>
          <span className="cfg__hint">الموبايل</span>
          <input
            className="input num" dir="ltr" inputMode="tel"
            value={form.phone}
            onChange={(e) => setForm({ ...form, phone: e.target.value })}
          />
        </label>
        <label>
          <span className="cfg__hint">النوع</span>
          <select
            className="input"
            value={form.gender}
            onChange={(e) => setForm({ ...form, gender: e.target.value })}
          >
            <option value="">—</option>
            <option value="male">ذكر</option>
            <option value="female">أنثى</option>
          </select>
        </label>
        <label>
          <span className="cfg__hint">تاريخ الميلاد</span>
          <input
            className="input" type="date"
            value={form.birth_date}
            onChange={(e) => setForm({ ...form, birth_date: e.target.value })}
          />
        </label>
        <label className="clinic__span2">
          <span className="cfg__hint">حساسية من أي دوا؟</span>
          <input
            className="input"
            placeholder="مثلاً: بنسلين"
            value={form.allergies_ar}
            onChange={(e) => setForm({ ...form, allergies_ar: e.target.value })}
          />
        </label>
        <label className="clinic__span2">
          <span className="cfg__hint">أمراض مزمنة</span>
          <input
            className="input"
            placeholder="مثلاً: ضغط وسكر"
            value={form.chronic_ar}
            onChange={(e) => setForm({ ...form, chronic_ar: e.target.value })}
          />
        </label>
      </div>

      {error ? <p className="clinic__error" role="alert">{error}</p> : null}

      <div className="row">
        <button type="submit" className="btn btn--brand" disabled={busy}>
          {busy ? 'لحظة…' : 'احفظ'}
        </button>
        <button type="button" className="btn btn--ghost" onClick={onCancel}>
          إلغاء
        </button>
        <span className="cfg__hint">
          رقم الملف بيتحدد لما البيانات توصل السيرفر.
        </span>
      </div>
    </form>
  );
}
