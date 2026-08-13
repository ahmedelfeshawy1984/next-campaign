'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { homeCounts, todayQueue, VISIT_STATUS_LABEL } from '@/lib/clinic/visits';
import { currentStaff, canExamine } from '@/lib/clinic/session';
import { loadCatalog } from '@/lib/clinic/drugs';
import { toArabicError } from '@/lib/clinic/errors';
import type { HomeCounts, QueueRow, ClinicStaff } from '@/lib/clinic/types';

// النهارده.
//
// The first screen of the day, and the only one most people will keep open.
// It answers three questions in order of how often they are asked: who is
// waiting, who is mine, and is this device ready to work without a network.

export default function ClinicToday() {
  const [staff, setStaff] = useState<ClinicStaff | null>(null);
  const [counts, setCounts] = useState<HomeCounts | null>(null);
  const [queue, setQueue] = useState<QueueRow[]>([]);
  const [drugs, setDrugs] = useState(0);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    void currentStaff().then(setStaff);
    void loadCatalog().then((c) => setDrugs(c.drugs));

    const load = () =>
      Promise.all([homeCounts(), todayQueue()])
        .then(([c, q]) => {
          setCounts(c);
          setQueue(q);
          setError(null);
        })
        .catch((e) => setError(toArabicError(e)));

    void load();
    // The queue is a shared live view — reception moves someone to "waiting"
    // on their machine and the doctor's screen has to notice without a reload.
    const t = window.setInterval(() => void load(), 20_000);
    return () => window.clearInterval(t);
  }, []);

  const mine = staff ? queue.filter((q) => q.doctor_id === staff.id) : [];
  const waiting = queue.filter((q) => q.status === 'waiting' || q.status === 'in_room');

  return (
    <>
      <h1>النهارده</h1>

      {error ? (
        <p className="clinic__warn" role="status">
          {error} — الأرقام اللي تحت ممكن تكون قديمة.
        </p>
      ) : null}

      <div className="clinic__cards">
        <Stat label="في الانتظار" value={counts?.waiting} />
        <Stat label="جوّه دلوقتي" value={counts?.in_room} />
        {canExamine(staff) ? <Stat label="مرضاي النهارده" value={counts?.mine_today} /> : null}
        <Stat label="خلصوا" value={counts?.done_today} />
      </div>

      {canExamine(staff) && mine.length > 0 ? (
        <section>
          <h2>اللي مستنيني</h2>
          <QueueList rows={mine} canExamine />
        </section>
      ) : null}

      <section>
        <h2>طابور العيادة</h2>
        {waiting.length === 0 ? (
          <p className="empty">مفيش حد في الانتظار.</p>
        ) : (
          <QueueList rows={waiting} canExamine={canExamine(staff)} />
        )}
      </section>

      {/* The honest readiness indicator. A doctor who knows the catalogue is on
          the device will not hesitate when the connection drops mid-session. */}
      <p className="cfg__hint clinic__ready">
        {drugs > 0
          ? `كتالوج الأدوية على الجهاز — ${drugs} دوا، البحث والطباعة شغّالين من غير نت.`
          : 'كتالوج الأدوية لسه ما نزلش على الجهاز — سيب الصفحة مفتوحة شوية والنت متوصّل.'}
      </p>
    </>
  );
}

function Stat({ label, value }: { label: string; value: number | undefined }) {
  return (
    <div className="clinic__card">
      <strong className="num">{value ?? '—'}</strong>
      <span>{label}</span>
    </div>
  );
}

function QueueList({ rows, canExamine: may }: { rows: QueueRow[]; canExamine: boolean }) {
  return (
    <ul className="clinic__queue">
      {rows.map((r) => (
        <li key={r.visit_id}>
          <div>
            <strong>{r.full_name}</strong>
            <span className="cfg__hint">
              {r.file_no ? <span className="num" dir="ltr">ملف {r.file_no}</span> : 'ملف جديد'}
              {' · '}
              {VISIT_STATUS_LABEL[r.status]}
              {r.doctor_name ? ` · ${r.doctor_name}` : ''}
            </span>
          </div>
          {may ? (
            <Link className="btn btn--brand btn--sm" href={`/clinic/visit/${r.patient_id}`}>
              ابدأ الكشف
            </Link>
          ) : null}
        </li>
      ))}
    </ul>
  );
}
