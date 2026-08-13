'use client';

import { useEffect, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import Link from 'next/link';
import RxBuilder from '@/components/clinic/RxBuilder';
import { currentStaff } from '@/lib/clinic/session';
import { getPatient, patientFile, ageLabel } from '@/lib/clinic/patients';
import {
  newPrescription, saveDraft, issuePrescription,
  newEncounter, saveEncounter,
} from '@/lib/clinic/rx';
import { toArabicError } from '@/lib/clinic/errors';
import type {
  ClinicStaff, Patient, Prescription, Encounter, RxItem, PatientFile,
} from '@/lib/clinic/types';

// شاشة الكشف.
//
// Everything the doctor does here is written to the device first and queued
// afterwards, so the screen never blocks on the network and the "اطبع" button
// is never disabled for want of one.

export default function VisitScreen() {
  const { patientId } = useParams<{ patientId: string }>();
  const router = useRouter();

  const [staff, setStaff] = useState<ClinicStaff | null>(null);
  const [patient, setPatient] = useState<Patient | null | undefined>(undefined);
  const [file, setFile] = useState<PatientFile | null>(null);
  const [fileError, setFileError] = useState<string | null>(null);

  const [enc, setEnc] = useState<Encounter | null>(null);
  const [rx, setRx] = useState<Prescription | null>(null);
  const [items, setItems] = useState<RxItem[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;

    (async () => {
      const s = await currentStaff();
      if (!alive) return;
      setStaff(s);

      const p = await getPatient(patientId);
      if (!alive) return;
      setPatient(p);

      if (s && p) {
        setEnc(newEncounter(p.id, s.id));
        setRx(await newPrescription(p.id, s));
      }

      // The shared clinic-wide history. Needs the network by definition — the
      // whole value of it is seeing what a COLLEAGUE prescribed, which is not
      // on this device. Failing here must not stop the doctor writing.
      try {
        const f = await patientFile(patientId);
        if (alive) setFile(f);
      } catch (e) {
        if (alive) setFileError(toArabicError(e));
      }
    })();

    return () => { alive = false; };
  }, [patientId]);

  if (patient === undefined) return <p className="empty">لحظة…</p>;
  if (!patient) return <p className="empty">مفيش مريض بالرقم ده.</p>;
  if (!staff || !rx || !enc) return <p className="empty">لحظة…</p>;

  const priorMeds = (file?.prescriptions ?? [])
    .filter((r) => r.status === 'issued' && !r.superseded)
    .slice(0, 3);

  async function issueAndPrint() {
    if (!rx) return;
    setBusy(true);
    setError(null);
    try {
      // The encounter goes first, always. The prescription references it, and
      // the outbox flushes oldest-first — reversing these two produces a
      // prescription whose encounter_id points at nothing for as long as the
      // clinic is offline.
      await saveEncounter({ ...enc!, status: 'issued' });
      const issued = await issuePrescription({ ...rx, items, encounter_id: enc!.id });
      router.push(`/clinic/rx/${issued.id}/print`);
    } catch (e) {
      setError(toArabicError(e));
      setBusy(false);
    }
  }

  return (
    <>
      <div className="row clinic__head">
        <h1>{patient.full_name}</h1>
        <span className="cfg__hint">
          {patient.file_no ? <span className="num" dir="ltr">ملف {patient.file_no}</span> : 'ملف جديد'}
          {patient.birth_date ? ` · ${ageLabel(patient.birth_date)}` : ''}
        </span>
        <span className="spacer" />
        <Link className="btn btn--ghost btn--sm" href={`/clinic/patients/${patient.id}`}>
          الملف الكامل
        </Link>
      </div>

      {/* ⚠ THE MOST IMPORTANT ELEMENT ON THIS PAGE. It sits above everything,
          it is red, and it is never behind a click. */}
      {patient.allergies_ar ? (
        <p className="clinic__allergy" role="alert">
          <strong>حساسية:</strong> {patient.allergies_ar}
        </p>
      ) : null}

      {patient.chronic_ar ? (
        <p className="clinic__chronic">
          <strong>أمراض مزمنة:</strong> {patient.chronic_ar}
        </p>
      ) : null}

      {/* What the patient is ALREADY taking, including from other doctors in
          this clinic. The reason the file is shared at all. */}
      {priorMeds.length > 0 ? (
        <section className="clinic__panel clinic__prior">
          <h2>ماشي على إيه دلوقتي</h2>
          {priorMeds.map((r) => (
            <div key={r.id} className="clinic__prior-rx">
              <span className="cfg__hint">
                {new Date(r.written_at).toLocaleDateString('ar-EG')} · {r.doctor_name ?? '—'}
              </span>
              <span>{r.items.map((i) => i.drug_name).join('، ')}</span>
            </div>
          ))}
        </section>
      ) : null}

      {fileError ? (
        <p className="clinic__warn">
          {fileError} تقدر تكشف وتكتب عادي، بس تاريخ المريض من الدكاترة التانيين
          مش ظاهر دلوقتي.
        </p>
      ) : null}

      <section className="clinic__panel">
        <h2>العلامات الحيوية</h2>
        <div className="clinic__vitals">
          <Vital label="ضغط ↑" value={enc.bp_sys} onChange={(v) => setEnc({ ...enc, bp_sys: v })} />
          <Vital label="ضغط ↓" value={enc.bp_dia} onChange={(v) => setEnc({ ...enc, bp_dia: v })} />
          <Vital label="نبض" value={enc.pulse} onChange={(v) => setEnc({ ...enc, pulse: v })} />
          <Vital label="حرارة" step="0.1" value={enc.temp_c as number | null}
                 onChange={(v) => setEnc({ ...enc, temp_c: v })} />
          <Vital label="وزن" step="0.1" value={enc.weight_kg as number | null}
                 onChange={(v) => setEnc({ ...enc, weight_kg: v })} />
          <Vital label="طول" step="0.1" value={enc.height_cm as number | null}
                 onChange={(v) => setEnc({ ...enc, height_cm: v })} />
        </div>
      </section>

      <section className="clinic__panel">
        <h2>الكشف</h2>
        <label>
          <span className="cfg__hint">الشكوى</span>
          <textarea className="input" rows={2}
            value={enc.complaint_ar ?? ''}
            onChange={(e) => setEnc({ ...enc, complaint_ar: e.target.value || null })} />
        </label>
        <label>
          <span className="cfg__hint">الفحص</span>
          <textarea className="input" rows={2}
            value={enc.exam_ar ?? ''}
            onChange={(e) => setEnc({ ...enc, exam_ar: e.target.value || null })} />
        </label>
        <label>
          <span className="cfg__hint">التشخيص</span>
          <textarea className="input" rows={2}
            value={enc.diagnosis_ar ?? ''}
            onChange={(e) => setEnc({ ...enc, diagnosis_ar: e.target.value || null })} />
        </label>
        <div className="clinic__grid2">
          <label>
            <span className="cfg__hint">تعليمات للمريض</span>
            <input className="input"
              value={enc.plan_ar ?? ''}
              onChange={(e) => setEnc({ ...enc, plan_ar: e.target.value || null })} />
          </label>
          <label>
            <span className="cfg__hint">ميعاد الإعادة</span>
            <input className="input" type="date"
              value={enc.next_visit_on ?? ''}
              onChange={(e) => setEnc({ ...enc, next_visit_on: e.target.value || null })} />
          </label>
        </div>
      </section>

      <section className="clinic__panel">
        <h2>
          الروشتة
          <span className="cfg__hint clinic__rxno num" dir="ltr">{rx.rx_no}</span>
        </h2>
        <RxBuilder items={items} onChange={setItems} disabled={busy} />
      </section>

      {error ? <p className="clinic__error" role="alert">{error}</p> : null}

      <div className="row clinic__actions">
        <button
          type="button"
          className="btn btn--brand"
          disabled={busy || items.length === 0}
          onClick={() => void issueAndPrint()}
        >
          {busy ? 'لحظة…' : 'أصدر واطبع'}
        </button>

        <button
          type="button"
          className="btn btn--ghost"
          disabled={busy}
          onClick={async () => {
            setBusy(true);
            setError(null);
            try {
              await saveEncounter(enc);
              await saveDraft({ ...rx, items, encounter_id: enc.id });
              setBusy(false);
            } catch (e) {
              setError(toArabicError(e));
              setBusy(false);
            }
          }}
        >
          احفظ كمسوّدة
        </button>

        <span className="cfg__hint">
          بعد ما تصدرها مش هتتعدّل — التعديل بيبقى نسخة جديدة.
        </span>
      </div>
    </>
  );
}

function Vital({
  label, value, onChange, step,
}: {
  label: string;
  value: number | null;
  onChange: (v: number | null) => void;
  step?: string;
}) {
  return (
    <label className="clinic__vital">
      <span className="cfg__hint">{label}</span>
      <input
        className="input num"
        dir="ltr"
        inputMode="decimal"
        type="number"
        step={step ?? '1'}
        value={value ?? ''}
        onChange={(e) => onChange(e.target.value === '' ? null : Number(e.target.value))}
      />
    </label>
  );
}
