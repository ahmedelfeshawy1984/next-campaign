'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import {
  reportByDoctor, reportPrescriptions, clinicians, type RxReportRow,
} from '@/lib/clinic/visits';
import { toArabicError } from '@/lib/clinic/errors';
import type { DoctorReportRow, ClinicStaff } from '@/lib/clinic/types';

// تقارير الديريكتور — «مين كشف لمين، وإيه اللي انكتب».
//
// Both halves in one screen, because they are one question. The top table is
// the count; the bottom list is the evidence, with the drugs on it — a report
// of "٢٤ روشتة" that cannot show what was in them answers nothing.
//
// The gate is clinic.report_by_doctor() and clinic.report_prescriptions(),
// both of which refuse anyone who is not the director INSIDE the function. The
// nav item being hidden from everyone else is a courtesy.

function isoDaysAgo(n: number): string {
  const d = new Date();
  d.setDate(d.getDate() - n);
  return d.toISOString().slice(0, 10);
}

export default function ReportsPage() {
  const [from, setFrom] = useState(() => isoDaysAgo(29));
  const [to, setTo] = useState(() => isoDaysAgo(0));
  const [doctorId, setDoctorId] = useState('');

  const [docs, setDocs] = useState<ClinicStaff[]>([]);
  const [rows, setRows] = useState<DoctorReportRow[]>([]);
  const [rxRows, setRxRows] = useState<RxReportRow[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(true);

  useEffect(() => {
    void clinicians().then(setDocs).catch(() => setDocs([]));
  }, []);

  useEffect(() => {
    setBusy(true);
    Promise.all([
      reportByDoctor(from, to),
      reportPrescriptions(from, to, doctorId || null),
    ])
      .then(([a, b]) => { setRows(a); setRxRows(b); setError(null); })
      .catch((e) => setError(toArabicError(e)))
      .finally(() => setBusy(false));
  }, [from, to, doctorId]);

  return (
    <>
      <h1>التقارير</h1>

      <div className="row clinic__filters">
        <label>
          <span className="cfg__hint">من</span>
          <input className="input num" type="date" dir="ltr"
            value={from} onChange={(e) => setFrom(e.target.value)} />
        </label>
        <label>
          <span className="cfg__hint">لـ</span>
          <input className="input num" type="date" dir="ltr"
            value={to} onChange={(e) => setTo(e.target.value)} />
        </label>
        <label>
          <span className="cfg__hint">الدكتور</span>
          <select className="input" value={doctorId}
            onChange={(e) => setDoctorId(e.target.value)}>
            <option value="">— كل الدكاترة —</option>
            {docs.map((d) => <option key={d.id} value={d.id}>{d.display_name}</option>)}
          </select>
        </label>
      </div>

      {error ? <p className="clinic__warn">{error}</p> : null}
      {busy ? <p className="empty">لحظة…</p> : null}

      <section>
        <h2>كل دكتور</h2>
        {rows.length === 0 ? (
          <p className="empty">مفيش شغل في المدة دي.</p>
        ) : (
          <table className="clinic__table">
            <thead>
              <tr>
                <th>الدكتور</th>
                <th>كشوفات</th>
                <th>مرضى</th>
                <th>روشتات</th>
                <th>المستحق</th>
                <th>المحصّل</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.doctor_id}>
                  <td>{r.doctor_name}</td>
                  <td className="num" dir="ltr">{r.visits}</td>
                  <td className="num" dir="ltr">{r.patients}</td>
                  <td className="num" dir="ltr">{r.prescriptions}</td>
                  <td className="num" dir="ltr">{Number(r.due).toFixed(2)}</td>
                  <td className="num" dir="ltr">{Number(r.collected).toFixed(2)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>

      <section>
        <h2>الروشتات اللي انكتبت <span className="cfg__hint num">({rxRows.length})</span></h2>
        {rxRows.length === 0 ? (
          <p className="empty">مفيش روشتات في المدة دي.</p>
        ) : (
          <ul className="clinic__timeline">
            {rxRows.map((r) => (
              <li key={r.rx_id} className={r.amended_from ? 'is-amend' : undefined}>
                <div className="row">
                  <strong className="num" dir="ltr">{r.rx_no}</strong>
                  <span className="cfg__hint">
                    {new Date(r.written_at).toLocaleDateString('ar-EG')} · {r.doctor_name}
                  </span>
                  {r.amended_from ? <span className="clinic__tag">نسخة معدّلة</span> : null}
                  <span className="spacer" />
                  <Link className="btn btn--ghost btn--sm" href={`/clinic/patients/${r.patient_id}`}>
                    {r.patient_name}
                    {r.file_no ? <span className="num" dir="ltr"> · {r.file_no}</span> : null}
                  </Link>
                </div>
                {r.diagnosis_ar ? (
                  <p className="cfg__hint">التشخيص: {r.diagnosis_ar}</p>
                ) : null}
                <p>{r.items.map((i) => i.drug_name).join('، ')}</p>
              </li>
            ))}
          </ul>
        )}
      </section>
    </>
  );
}
