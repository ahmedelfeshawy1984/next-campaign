'use client';

import { useEffect, useState } from 'react';
import { useParams } from 'next/navigation';
import Link from 'next/link';
import { patientFile, ageLabel } from '@/lib/clinic/patients';
import { amendPrescription } from '@/lib/clinic/rx';
import { currentStaff, canExamine } from '@/lib/clinic/session';
import { toArabicError } from '@/lib/clinic/errors';
import { prettyPhone } from '@/lib/phone.js';
import type { PatientFile, ClinicStaff } from '@/lib/clinic/types';

// ملف المريض — مشترك بين كل دكاترة العيادة.
//
// Every entry carries the name of the doctor who wrote it. That is the whole
// bargain of a shared file: anyone here can read the history, nobody can
// author under someone else's name, and the page says who wrote what without
// being asked.

export default function PatientFilePage() {
  const { id } = useParams<{ id: string }>();
  const [staff, setStaff] = useState<ClinicStaff | null>(null);
  const [file, setFile] = useState<PatientFile | null | undefined>(undefined);
  const [error, setError] = useState<string | null>(null);

  const load = () =>
    patientFile(id)
      .then(setFile)
      .catch((e) => {
        setError(toArabicError(e));
        setFile(null);
      });

  useEffect(() => {
    void currentStaff().then(setStaff);
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  if (file === undefined) return <p className="empty">لحظة…</p>;
  if (!file) return <p className="empty">{error ?? 'مفيش ملف بالرقم ده.'}</p>;

  const p = file.patient;

  return (
    <>
      <div className="row clinic__head">
        <h1>{p.full_name}</h1>
        <span className="spacer" />
        {canExamine(staff) ? (
          <Link className="btn btn--brand btn--sm" href={`/clinic/visit/${p.id}`}>
            كشف جديد
          </Link>
        ) : null}
      </div>

      <dl className="clinic__facts">
        <dt>رقم الملف</dt>
        <dd className="num" dir="ltr">{p.file_no ?? 'لسه ما اترفعش'}</dd>
        <dt>الموبايل</dt>
        <dd className="num" dir="ltr">{p.phone ? prettyPhone(p.phone) : '—'}</dd>
        <dt>السن</dt>
        <dd>{ageLabel(p.birth_date)}</dd>
        <dt>النوع</dt>
        <dd>{p.gender === 'male' ? 'ذكر' : p.gender === 'female' ? 'أنثى' : '—'}</dd>
      </dl>

      {p.allergies_ar ? (
        <p className="clinic__allergy" role="alert">
          <strong>حساسية:</strong> {p.allergies_ar}
        </p>
      ) : null}
      {p.chronic_ar ? (
        <p className="clinic__chronic"><strong>أمراض مزمنة:</strong> {p.chronic_ar}</p>
      ) : null}

      <section>
        <h2>الروشتات</h2>
        {file.prescriptions.length === 0 ? (
          <p className="empty">مفيش روشتات لسه.</p>
        ) : (
          <ul className="clinic__timeline">
            {file.prescriptions.map((r) => (
              <li key={r.id} className={r.superseded ? 'is-superseded' : undefined}>
                <div className="row">
                  <strong className="num" dir="ltr">{r.rx_no}</strong>
                  <span className="cfg__hint">
                    {new Date(r.written_at).toLocaleDateString('ar-EG')} · {r.doctor_name}
                  </span>
                  {r.superseded ? <span className="clinic__tag">اتعدّلت</span> : null}
                  {r.status !== 'issued' ? <span className="clinic__tag">مسوّدة</span> : null}
                  <span className="spacer" />
                  <Link className="btn btn--ghost btn--sm" href={`/clinic/rx/${r.id}/print`}>
                    اطبع
                  </Link>
                  {canExamine(staff) && r.status === 'issued' && !r.superseded ? (
                    <AmendButton id={r.id} onDone={load} />
                  ) : null}
                </div>
                <ol className="clinic__rx-items">
                  {r.items.map((i, n) => (
                    <li key={n}>
                      <strong>{i.drug_name}</strong>{' '}
                      {[i.dose_ar, i.frequency_ar, i.duration_ar].filter(Boolean).join(' · ')}
                    </li>
                  ))}
                </ol>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section>
        <h2>الكشوفات</h2>
        {file.encounters.length === 0 ? (
          <p className="empty">مفيش كشوفات مسجّلة.</p>
        ) : (
          <ul className="clinic__timeline">
            {file.encounters.map((e) => (
              <li key={e.id}>
                <div className="row">
                  <span className="cfg__hint">
                    {e.created_at ? new Date(e.created_at).toLocaleDateString('ar-EG') : ''}
                    {' · '}{e.doctor_name}
                  </span>
                </div>
                {e.diagnosis_ar ? <p><strong>التشخيص:</strong> {e.diagnosis_ar}</p> : null}
                {e.complaint_ar ? <p className="cfg__hint">{e.complaint_ar}</p> : null}
                {(e.bp_sys || e.pulse || e.temp_c) ? (
                  <p className="cfg__hint num" dir="ltr">
                    {e.bp_sys ? `BP ${e.bp_sys}/${e.bp_dia ?? '—'} ` : ''}
                    {e.pulse ? `· HR ${e.pulse} ` : ''}
                    {e.temp_c ? `· T ${e.temp_c}` : ''}
                  </p>
                ) : null}
              </li>
            ))}
          </ul>
        )}
      </section>
    </>
  );
}

function AmendButton({ id, onDone }: { id: string; onDone: () => void }) {
  const [asking, setAsking] = useState(false);
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);

  if (!asking) {
    return (
      <button type="button" className="btn btn--ghost btn--sm" onClick={() => setAsking(true)}>
        نسخة معدّلة
      </button>
    );
  }

  return (
    <span className="clinic__amend">
      <input
        className="input btn--sm"
        placeholder="سبب التعديل"
        value={reason}
        onChange={(e) => setReason(e.target.value)}
        autoFocus
      />
      <button
        type="button"
        className="btn btn--brand btn--sm"
        onClick={async () => {
          try {
            const next = await amendPrescription(id, reason);
            setAsking(false);
            onDone();
            window.location.assign(`/clinic/rx/${next}/print`);
          } catch (e) {
            setError(toArabicError(e));
          }
        }}
      >
        تمام
      </button>
      {error ? <span className="clinic__error">{error}</span> : null}
    </span>
  );
}
