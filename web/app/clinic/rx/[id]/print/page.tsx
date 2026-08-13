'use client';

import { useEffect, useState } from 'react';
import { useParams } from 'next/navigation';
import { getPrescription, markPrinted } from '@/lib/clinic/rx';
import { getPatient, ageLabel } from '@/lib/clinic/patients';
import { clinicSettings } from '@/lib/clinic/visits';
import { currentStaff } from '@/lib/clinic/session';
import type { Prescription, Patient, ClinicSettings, ClinicStaff } from '@/lib/clinic/types';
import './print.css';

// الروشتة — الصفحة اللي بتتطبع.
//
// READS FROM INDEXEDDB FIRST, always. This page must render with the network
// unplugged, because that is the exact moment it matters: the patient is
// standing at the desk and the clinic's connection just died. getPrescription()
// looks locally before it looks anywhere else, and the prescription this
// device wrote is by construction the same record the server will hold.
//
// The paper already carries the clinic's letterhead. What prints is the part
// that changes — and the offsets that keep it off the printed header come from
// clinic.settings, not from the stylesheet.

export default function PrintPrescription() {
  const { id } = useParams<{ id: string }>();

  const [rx, setRx] = useState<Prescription | null | undefined>(undefined);
  const [patient, setPatient] = useState<Patient | null>(null);
  const [settings, setSettings] = useState<ClinicSettings | null>(null);
  const [doctor, setDoctor] = useState<ClinicStaff | null>(null);

  useEffect(() => {
    (async () => {
      const found = await getPrescription(id).catch(() => null);
      setRx(found);
      if (found) setPatient(await getPatient(found.patient_id).catch(() => null));
      setDoctor(await currentStaff().catch(() => null));
      // Settings are cosmetic here — margins and a clinic name. A failure must
      // not stop a prescription printing, so the stylesheet's fallbacks stand.
      setSettings(await clinicSettings().catch(() => null));
    })();
  }, [id]);

  if (rx === undefined) return <p className="empty">لحظة…</p>;
  if (!rx) {
    return (
      <p className="empty">
        مفيش روشتة بالرقم ده على الجهاز ده. لو اتكتبت على جهاز تاني، افتحها من
        ملف المريض والنت متوصّل.
      </p>
    );
  }

  const printHeader = settings?.print_header ?? false;
  const style = {
    '--rx-header-mm': printHeader ? '10mm' : `${Number(settings?.header_offset_mm ?? 35)}mm`,
    '--rx-footer-mm': `${Number(settings?.footer_offset_mm ?? 20)}mm`,
    '--rx-margin-mm': `${Number(settings?.margin_x_mm ?? 12)}mm`,
  } as React.CSSProperties;

  const written = new Date(rx.written_at);

  return (
    <>
      <div className="rx__toolbar">
        <button
          type="button"
          className="btn btn--brand"
          onClick={() => {
            window.print();
            void markPrinted(rx.id);
          }}
        >
          اطبع
        </button>
        <span className="cfg__hint">
          متظبطة على A5. لو الورق أبيض من غير ترويسة، شغّل
          «اطبع الترويسة» من الإعدادات.
        </span>
        {rx.status !== 'issued' ? (
          <span className="cfg__hint">دي لسه مسوّدة.</span>
        ) : null}
      </div>

      <article className="rx rx--screen" style={style}>
        {printHeader ? (
          <header className="rx__head">
            {/* A data: URI, so it is already in the page rather than fetched.
                A logo loaded from a bucket would be a blank space on every
                sheet printed while the clinic's internet was down — which is
                exactly when this system is meant to keep working. */}
            {settings?.logo_url ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={settings.logo_url} alt="" className="rx__logo" />
            ) : null}
            <h1>{settings?.clinic_name_ar ?? 'العيادة'}</h1>
            <p>
              {doctor?.display_name}
              {doctor?.specialty_ar ? ` — ${doctor.specialty_ar}` : ''}
            </p>
            <p>
              {settings?.address_ar}
              {settings?.phone ? (
                <> · <span className="num" dir="ltr">{settings.phone}</span></>
              ) : null}
            </p>
          </header>
        ) : null}

        {rx.status !== 'issued' ? <p className="rx__draft">مسوّدة — لسه ما اتصدرتش</p> : null}

        {rx.amended_from ? (
          <p className="rx__draft">
            نسخة معدّلة — بتلغي روشتة سابقة
            {rx.amend_reason ? `: ${rx.amend_reason}` : ''}
          </p>
        ) : null}

        <div className="rx__meta">
          <span>
            <strong>{patient?.full_name ?? '—'}</strong>
            {patient?.birth_date ? ` · ${ageLabel(patient.birth_date)}` : ''}
            {patient?.file_no ? (
              <> · <span className="num" dir="ltr">ملف {patient.file_no}</span></>
            ) : null}
          </span>
          <span className="num" dir="ltr">
            {written.toLocaleDateString('ar-EG')}
          </span>
        </div>

        {/* Printed, not just shown. The pharmacist is the last person who can
            catch a prescription that contradicts a known allergy. */}
        {patient?.allergies_ar ? (
          <p className="rx__allergy">⚠ حساسية: {patient.allergies_ar}</p>
        ) : null}

        <div className="rx__rx" aria-hidden="true">℞</div>

        <ol className="rx__lines">
          {rx.items.map((item, i) => (
            <li className="rx__line" key={i}>
              <span className="rx__line-no num">{i + 1}.</span>
              <span>
                <span className="rx__line-name">
                  {item.drug_name}
                  {item.strength ? (
                    <span className="num" dir="ltr"> {item.strength}</span>
                  ) : null}
                  {item.form_ar ? <> — {item.form_ar}</> : null}
                </span>
                <br />
                <span className="rx__line-how">
                  {[item.dose_ar, item.frequency_ar, item.duration_ar]
                    .filter(Boolean)
                    .join(' · ')}
                </span>
                {item.notes_ar ? (
                  <>
                    <br />
                    <span className="rx__line-note">{item.notes_ar}</span>
                  </>
                ) : null}
              </span>
            </li>
          ))}
        </ol>

        <footer className="rx__foot">
          <div>
            {/* Which doctor wrote this. With several of them sharing one clinic
                and one pad, a sheet without a name on it is anonymous paper. */}
            <div>
              <strong>{doctor?.display_name ?? ''}</strong>
              {doctor?.title_ar ? ` — ${doctor.title_ar}` : ''}
            </div>
            {doctor?.syndicate_no ? (
              <div className="num" dir="ltr">نقابة: {doctor.syndicate_no}</div>
            ) : null}
            <div className="num" dir="ltr">{rx.rx_no}</div>
          </div>
          <div className="rx__sign">
            <div className="rx__sign-line">التوقيع</div>
          </div>
        </footer>
      </article>
    </>
  );
}
