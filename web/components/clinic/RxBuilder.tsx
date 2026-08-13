'use client';

import { useState } from 'react';
import DrugPicker from './DrugPicker';
import type { Drug, RxItem } from '@/lib/clinic/types';

// بناء الروشتة سطر سطر.
//
// The dose, frequency and duration fields carry suggestion lists rather than
// dropdowns. A dropdown of "٣ مرات يوميًا" is right until the day somebody
// needs "كل ٨ ساعات لمدة ٥ أيام بعد الأكل", and a doctor who cannot write what
// they mean stops using the system and goes back to the pad.

const FREQUENCY = ['مرة يوميًا', 'مرتين يوميًا', '٣ مرات يوميًا', '٤ مرات يوميًا',
                   'كل ٨ ساعات', 'كل ١٢ ساعة', 'عند اللزوم', 'قبل النوم'];
const DURATION  = ['٣ أيام', '٥ أيام', '٧ أيام', '١٠ أيام', 'أسبوعين', 'شهر', 'مستمر'];
const DOSE      = ['قرص', 'نص قرص', 'قرصين', 'كبسولة', 'ملعقة', 'ملعقة صغيرة',
                   'نقطة', '٥ مل', '١٠ مل'];
const NOTES     = ['بعد الأكل', 'قبل الأكل بساعة', 'على الريق', 'مع الأكل', 'قبل النوم'];

function blank(): RxItem {
  return {
    drug_id: null, drug_name: '', form_ar: null, strength: null,
    dose_ar: null, frequency_ar: null, duration_ar: null,
    route_ar: null, notes_ar: null,
  };
}

interface Props {
  items: RxItem[];
  onChange: (items: RxItem[]) => void;
  disabled?: boolean;
}

export default function RxBuilder({ items, onChange, disabled }: Props) {
  const [rows, setRows] = useState<RxItem[]>(items.length ? items : [blank()]);

  function commit(next: RxItem[]) {
    setRows(next);
    // Blank trailing rows are scaffolding, not prescription lines. Filtering
    // here rather than at save time means the count the doctor sees on the
    // screen is the count that prints.
    onChange(next.filter((r) => r.drug_name.trim() !== ''));
  }

  function patch(i: number, changes: Partial<RxItem>) {
    commit(rows.map((r, j) => (j === i ? { ...r, ...changes } : r)));
  }

  return (
    <div className="rxb">
      {rows.map((row, i) => (
        <div className="rxb__row" key={i}>
          <div className="rxb__no num">{i + 1}</div>

          <div className="rxb__fields">
            <DrugPicker
              value={row.drug_name}
              autoFocus={i === rows.length - 1 && row.drug_name === '' && i > 0}
              onPick={(drug: Drug | null, typed: string) =>
                patch(i, {
                  drug_name: typed,
                  drug_id: drug?.id ?? null,
                  form_ar: drug?.form_ar || row.form_ar,
                  strength: drug?.strength || row.strength,
                })
              }
            />

            <div className="rxb__grid">
              <label>
                <span className="cfg__hint">الجرعة</span>
                <input
                  className="input" list="rx-dose" disabled={disabled}
                  value={row.dose_ar ?? ''}
                  onChange={(e) => patch(i, { dose_ar: e.target.value || null })}
                />
              </label>
              <label>
                <span className="cfg__hint">كام مرة</span>
                <input
                  className="input" list="rx-freq" disabled={disabled}
                  value={row.frequency_ar ?? ''}
                  onChange={(e) => patch(i, { frequency_ar: e.target.value || null })}
                />
              </label>
              <label>
                <span className="cfg__hint">المدة</span>
                <input
                  className="input" list="rx-dur" disabled={disabled}
                  value={row.duration_ar ?? ''}
                  onChange={(e) => patch(i, { duration_ar: e.target.value || null })}
                />
              </label>
              <label>
                <span className="cfg__hint">ملاحظات</span>
                <input
                  className="input" list="rx-notes" disabled={disabled}
                  value={row.notes_ar ?? ''}
                  onChange={(e) => patch(i, { notes_ar: e.target.value || null })}
                />
              </label>
            </div>
          </div>

          <button
            type="button"
            className="btn btn--ghost btn--sm rxb__del"
            disabled={disabled || rows.length === 1}
            onClick={() => commit(rows.filter((_, j) => j !== i))}
            aria-label={`امسح السطر ${i + 1}`}
          >
            ✕
          </button>
        </div>
      ))}

      <button
        type="button"
        className="btn btn--ghost"
        disabled={disabled}
        onClick={() => commit([...rows, blank()])}
      >
        + سطر جديد
      </button>

      {/* Suggestions, not constraints — see the note at the top of this file. */}
      <datalist id="rx-dose">{DOSE.map((v) => <option key={v} value={v} />)}</datalist>
      <datalist id="rx-freq">{FREQUENCY.map((v) => <option key={v} value={v} />)}</datalist>
      <datalist id="rx-dur">{DURATION.map((v) => <option key={v} value={v} />)}</datalist>
      <datalist id="rx-notes">{NOTES.map((v) => <option key={v} value={v} />)}</datalist>
    </div>
  );
}
