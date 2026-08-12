'use client';

import { useEffect, useState } from 'react';
import { daySheet, PAY_METHOD_LABEL, type DaySheet } from '@/lib/clinic/visits';
import { toArabicError } from '@/lib/clinic/errors';
import type { PayMethod } from '@/lib/clinic/types';

// حساب اليوم — بيتقفل عليه الدرج.
//
// Shows what the visits SHOULD have brought in next to what actually reached
// the drawer. Showing only the second number hides the gap, and the gap is the
// only number on this page anybody needs to act on.

export default function DayPage() {
  const [day, setDay] = useState(() => new Date().toISOString().slice(0, 10));
  const [sheet, setSheet] = useState<DaySheet | null | undefined>(undefined);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setSheet(undefined);
    daySheet(day)
      .then(setSheet)
      .catch((e) => { setError(toArabicError(e)); setSheet(null); });
  }, [day]);

  const due = Number(sheet?.due ?? 0);
  const collected = Number(sheet?.collected ?? 0);
  const gap = due - collected;

  return (
    <>
      <div className="row clinic__head">
        <h1>حساب اليوم</h1>
        <span className="spacer" />
        <input
          className="input num" type="date" dir="ltr"
          value={day} onChange={(e) => setDay(e.target.value)}
        />
      </div>

      {error ? <p className="clinic__warn">{error}</p> : null}
      {sheet === undefined ? <p className="empty">لحظة…</p> : null}

      {sheet ? (
        <>
          <div className="clinic__cards">
            <div className="clinic__card">
              <strong className="num">{sheet.visits}</strong>
              <span>كشوفات خلصت</span>
            </div>
            <div className="clinic__card">
              <strong className="num" dir="ltr">{due.toFixed(2)}</strong>
              <span>المستحق</span>
            </div>
            <div className="clinic__card">
              <strong className="num" dir="ltr">{collected.toFixed(2)}</strong>
              <span>اللي اتحصّل</span>
            </div>
            <div className={`clinic__card${gap > 0 ? ' clinic__card--warn' : ''}`}>
              <strong className="num" dir="ltr">{gap.toFixed(2)}</strong>
              <span>الفرق</span>
            </div>
          </div>

          <section>
            <h2>حسب طريقة الدفع</h2>
            {Object.keys(sheet.by_method ?? {}).length === 0 ? (
              <p className="empty">مفيش متحصلات في اليوم ده.</p>
            ) : (
              <ul className="clinic__facts-list">
                {Object.entries(sheet.by_method).map(([m, total]) => (
                  <li key={m}>
                    <span>{PAY_METHOD_LABEL[m as PayMethod] ?? m}</span>
                    <strong className="num" dir="ltr">{Number(total).toFixed(2)}</strong>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </>
      ) : null}
    </>
  );
}
