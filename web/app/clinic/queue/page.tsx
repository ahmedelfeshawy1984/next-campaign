'use client';

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import {
  todayQueue, setVisitStatus, bookVisit, clinicians, takePayment,
  VISIT_STATUS_LABEL,
} from '@/lib/clinic/visits';
import { searchPatients } from '@/lib/clinic/patients';
import { currentStaff, canExamine } from '@/lib/clinic/session';
import { toArabicError } from '@/lib/clinic/errors';
import type { QueueRow, ClinicStaff, PatientSearchRow, VisitStatus } from '@/lib/clinic/types';

// لوحة الاستقبال.
//
// Needs a network and says so when it does not have one, rather than showing a
// stale board. A queue is several people acting at once; a copy of it from
// four minutes ago is worse than no copy, because it looks current.

export default function QueuePage() {
  const [staff, setStaff] = useState<ClinicStaff | null>(null);
  const [rows, setRows] = useState<QueueRow[]>([]);
  const [docs, setDocs] = useState<ClinicStaff[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [adding, setAdding] = useState(false);

  const load = useCallback(
    () =>
      todayQueue()
        .then((r) => { setRows(r); setError(null); })
        .catch((e) => setError(toArabicError(e))),
    []
  );

  useEffect(() => {
    void currentStaff().then(setStaff);
    void clinicians().then(setDocs).catch(() => setDocs([]));
    void load();
    const t = window.setInterval(() => void load(), 15_000);
    return () => window.clearInterval(t);
  }, [load]);

  async function move(id: string, status: VisitStatus) {
    try {
      await setVisitStatus(id, status);
      await load();
    } catch (e) {
      setError(toArabicError(e));
    }
  }

  return (
    <>
      <div className="row clinic__head">
        <h1>الطابور</h1>
        <span className="spacer" />
        <button type="button" className="btn btn--brand" onClick={() => setAdding(!adding)}>
          + ضيف للطابور
        </button>
      </div>

      {error ? <p className="clinic__warn" role="status">{error}</p> : null}

      {adding ? (
        <AddToQueue
          doctors={docs}
          onDone={() => { setAdding(false); void load(); }}
          onError={setError}
        />
      ) : null}

      {rows.length === 0 ? (
        <p className="empty">الطابور فاضي النهارده.</p>
      ) : (
        <table className="clinic__table">
          <thead>
            <tr>
              <th>المريض</th>
              <th>الدكتور</th>
              <th>الحالة</th>
              <th>المستحق</th>
              <th>اتدفع</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.visit_id}>
                <td>
                  <strong>{r.full_name}</strong>
                  <br />
                  <span className="cfg__hint num" dir="ltr">
                    {r.file_no ? `ملف ${r.file_no}` : 'ملف جديد'}
                  </span>
                </td>
                <td>{r.doctor_name ?? '—'}</td>
                <td>{VISIT_STATUS_LABEL[r.status]}</td>
                <td className="num" dir="ltr">{Number(r.fee).toFixed(2)}</td>
                <td className="num" dir="ltr">{Number(r.paid).toFixed(2)}</td>
                <td className="row">
                  {r.status === 'booked' ? (
                    <button className="btn btn--ghost btn--sm"
                      onClick={() => void move(r.visit_id, 'waiting')}>وصل</button>
                  ) : null}
                  {r.status === 'waiting' ? (
                    <button className="btn btn--ghost btn--sm"
                      onClick={() => void move(r.visit_id, 'in_room')}>دخل</button>
                  ) : null}
                  {r.status === 'in_room' ? (
                    <button className="btn btn--ghost btn--sm"
                      onClick={() => void move(r.visit_id, 'done')}>خلص</button>
                  ) : null}

                  {Number(r.paid) < Number(r.fee) && staff?.role !== 'doctor' ? (
                    <button
                      className="btn btn--ghost btn--sm"
                      onClick={async () => {
                        try {
                          await takePayment(r.visit_id, Number(r.fee) - Number(r.paid));
                          await load();
                        } catch (e) { setError(toArabicError(e)); }
                      }}
                    >
                      حصّل
                    </button>
                  ) : null}

                  {canExamine(staff) ? (
                    <Link className="btn btn--brand btn--sm" href={`/clinic/visit/${r.patient_id}`}>
                      كشف
                    </Link>
                  ) : null}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </>
  );
}

function AddToQueue({
  doctors, onDone, onError,
}: {
  doctors: ClinicStaff[];
  onDone: () => void;
  onError: (m: string) => void;
}) {
  const [term, setTerm] = useState('');
  const [hits, setHits] = useState<PatientSearchRow[]>([]);
  const [doctorId, setDoctorId] = useState('');

  useEffect(() => {
    const t = window.setTimeout(() => {
      if (term.trim()) void searchPatients(term).then(setHits).catch(() => setHits([]));
      else setHits([]);
    }, 250);
    return () => window.clearTimeout(t);
  }, [term]);

  return (
    <div className="clinic__panel">
      <h2>ضيف مريض للطابور</h2>
      <div className="clinic__grid2">
        <label>
          <span className="cfg__hint">ابحث عن المريض</span>
          <input className="input" value={term} autoFocus
            onChange={(e) => setTerm(e.target.value)} placeholder="اسم أو موبايل…" />
        </label>
        <label>
          <span className="cfg__hint">الدكتور</span>
          <select className="input" value={doctorId} onChange={(e) => setDoctorId(e.target.value)}>
            <option value="">— أي دكتور —</option>
            {doctors.map((d) => (
              <option key={d.id} value={d.id}>{d.display_name}</option>
            ))}
          </select>
        </label>
      </div>

      <ul className="clinic__patients">
        {hits.map((p) => (
          <li key={p.id}>
            <div>
              <strong>{p.full_name}</strong>
              <span className="cfg__hint num" dir="ltr">
                {p.file_no ? `ملف ${p.file_no}` : 'ملف جديد'}
              </span>
            </div>
            <button
              className="btn btn--brand btn--sm"
              onClick={async () => {
                try {
                  await bookVisit(p.id, doctorId || null);
                  onDone();
                } catch (e) { onError(toArabicError(e)); }
              }}
            >
              ضيفه
            </button>
          </li>
        ))}
      </ul>

      <p className="cfg__hint">
        السعر بيتحدد لوحده: إعادة لو جه خلال المدة المحدّدة في الإعدادات، وكشف
        جديد غير كده.
      </p>
    </div>
  );
}
