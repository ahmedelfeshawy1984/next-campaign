'use client';

import { useCallback, useEffect, useState } from 'react';
import { clinicSupabase } from '@/lib/clinic/supabase';
import { syncCatalog } from '@/lib/clinic/drugs';
import { parseDrugList, COLUMN_LABEL } from '@/lib/clinic/drugImport.js';
import { toArabicError } from '@/lib/clinic/errors';
import { currentStaff, isDirector } from '@/lib/clinic/session';
import type { ClinicStaff } from '@/lib/clinic/types';

// كتالوج الأدوية.
//
// The catalogue that ships is a hundred common brands — enough that the picker
// is useful on day one, and nowhere near the clinic's real list. This screen is
// how the real one gets in, and the import box is the important half: the list
// already exists somewhere, in Excel or the old system, and retyping it is why
// features like this go unused.

interface DrugRow {
  id: string;
  trade_name: string;
  trade_name_ar: string;
  generic_ar: string | null;
  generic_en: string | null;
  form_ar: string;
  strength: string;
  is_active: boolean;
  uses: number;
}

export default function DrugsPage() {
  const [staff, setStaff] = useState<ClinicStaff | null>(null);
  const [term, setTerm] = useState('');
  const [rows, setRows] = useState<DrugRow[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [tab, setTab] = useState<'list' | 'import'>('list');

  const load = useCallback(async (search: string) => {
    try {
      const { data, error: e } = await clinicSupabase().rpc('list_drugs', {
        p_term: search || null,
        p_limit: 200,
      });
      if (e) throw e;
      setRows((data ?? []) as DrugRow[]);
      setError(null);
    } catch (e) {
      setError(toArabicError(e));
    }
  }, []);

  useEffect(() => { void currentStaff().then(setStaff); }, []);

  useEffect(() => {
    const t = window.setTimeout(() => void load(term), 250);
    return () => window.clearTimeout(t);
  }, [term, load]);

  async function setActive(d: DrugRow, active: boolean) {
    setBusy(true);
    try {
      const { error: e } = await clinicSupabase()
        .from('drugs').update({ is_active: active }).eq('id', d.id);
      if (e) throw e;
      await load(term);
      // The device holds its own copy; without this the picker goes on
      // offering a drug the clinic has just withdrawn.
      await syncCatalog().catch(() => {});
    } catch (e) {
      setError(toArabicError(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <div className="row clinic__head">
        <h1>كتالوج الأدوية</h1>
        <span className="spacer" />
        <div className="row">
          <button
            type="button"
            className={`btn btn--sm ${tab === 'list' ? 'btn--brand' : 'btn--ghost'}`}
            onClick={() => setTab('list')}
          >
            القايمة
          </button>
          {isDirector(staff) ? (
            <button
              type="button"
              className={`btn btn--sm ${tab === 'import' ? 'btn--brand' : 'btn--ghost'}`}
              onClick={() => setTab('import')}
            >
              استيراد قايمة
            </button>
          ) : null}
        </div>
      </div>

      {error ? <p className="clinic__warn">{error}</p> : null}

      {tab === 'import' ? (
        <ImportPanel
          onDone={async () => { setTab('list'); await load(term); }}
          onError={setError}
        />
      ) : (
        <>
          <div className="row clinic__filters">
            <input
              className="input"
              placeholder="ابحث بالاسم أو المادة الفعالة…"
              value={term}
              onChange={(e) => setTerm(e.target.value)}
              autoFocus
            />
            {isDirector(staff) ? (
              <AddDrug onDone={() => void load(term)} onError={setError} />
            ) : null}
          </div>

          <p className="cfg__hint">
            {rows.length} دوا معروضين. الأدوية الموقوفة مش بتظهر للدكتور وهو
            بيكتب الروشتة.
          </p>

          <table className="clinic__table">
            <thead>
              <tr>
                <th>الاسم التجاري</th>
                <th>بالعربي</th>
                <th>المادة الفعالة</th>
                <th>الشكل</th>
                <th>التركيز</th>
                <th>اتكتب كام مرة</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {rows.map((d) => (
                <tr key={d.id} className={d.is_active ? undefined : 'is-off'}>
                  <td><strong>{d.trade_name}</strong></td>
                  <td>{d.trade_name_ar || '—'}</td>
                  <td>{d.generic_ar || d.generic_en || '—'}</td>
                  <td>{d.form_ar || '—'}</td>
                  <td className="num" dir="ltr">{d.strength || '—'}</td>
                  <td className="num" dir="ltr">{d.uses}</td>
                  <td>
                    {isDirector(staff) ? (
                      <button
                        className="btn btn--ghost btn--sm"
                        disabled={busy}
                        onClick={() => void setActive(d, !d.is_active)}
                      >
                        {d.is_active ? 'وقّفه' : 'رجّعه'}
                      </button>
                    ) : null}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </>
      )}
    </>
  );
}

function AddDrug({ onDone, onError }: { onDone: () => void; onError: (m: string) => void }) {
  const [open, setOpen] = useState(false);
  const [f, setF] = useState({
    trade_name: '', trade_name_ar: '', generic_ar: '', form_ar: '', strength: '',
  });
  const [busy, setBusy] = useState(false);

  if (!open) {
    return (
      <button type="button" className="btn btn--brand" onClick={() => setOpen(true)}>
        + دوا جديد
      </button>
    );
  }

  return (
    <form
      className="clinic__panel clinic__span2"
      onSubmit={async (e) => {
        e.preventDefault();
        setBusy(true);
        try {
          const { error } = await clinicSupabase().rpc('add_drug', {
            p_trade_name: f.trade_name,
            p_generic_ar: f.generic_ar || null,
            p_form_ar: f.form_ar,
            p_strength: f.strength,
            p_trade_name_ar: f.trade_name_ar,
          });
          if (error) throw error;
          await syncCatalog().catch(() => {});
          setF({ trade_name: '', trade_name_ar: '', generic_ar: '', form_ar: '', strength: '' });
          setOpen(false);
          onDone();
        } catch (err) {
          onError(toArabicError(err));
        } finally {
          setBusy(false);
        }
      }}
    >
      <h2>دوا جديد</h2>
      <div className="clinic__grid2">
        <label>
          <span className="cfg__hint">الاسم التجاري</span>
          <input className="input" required autoFocus value={f.trade_name}
            onChange={(e) => setF({ ...f, trade_name: e.target.value })} />
        </label>
        <label>
          <span className="cfg__hint">الاسم بالعربي — عشان الدكتور يلاقيه لما يكتب عربي</span>
          <input className="input" placeholder="كونكور" value={f.trade_name_ar}
            onChange={(e) => setF({ ...f, trade_name_ar: e.target.value })} />
        </label>
        <label>
          <span className="cfg__hint">المادة الفعالة</span>
          <input className="input" value={f.generic_ar}
            onChange={(e) => setF({ ...f, generic_ar: e.target.value })} />
        </label>
        <label>
          <span className="cfg__hint">الشكل</span>
          <input className="input" placeholder="أقراص" value={f.form_ar}
            onChange={(e) => setF({ ...f, form_ar: e.target.value })} />
        </label>
        <label>
          <span className="cfg__hint">التركيز</span>
          <input className="input" placeholder="500 مجم" value={f.strength}
            onChange={(e) => setF({ ...f, strength: e.target.value })} />
        </label>
      </div>
      <div className="row">
        <button type="submit" className="btn btn--brand" disabled={busy}>
          {busy ? 'لحظة…' : 'احفظ'}
        </button>
        <button type="button" className="btn btn--ghost" onClick={() => setOpen(false)}>
          إلغاء
        </button>
      </div>
    </form>
  );
}

// ---------------------------------------------------------------------------
//  الاستيراد
//
//  Always previews before it writes. Somebody pasting three hundred rows of
//  their own drug list needs to see that the columns landed where they think
//  they did — a silent import that put the strength in the Arabic-name column
//  is worse than a refusal, because it looks like it worked.
// ---------------------------------------------------------------------------
function ImportPanel({
  onDone, onError,
}: {
  onDone: () => Promise<void>;
  onError: (m: string) => void;
}) {
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<string | null>(null);

  const parsed = parseDrugList(text);

  return (
    <div className="clinic__panel">
      <h2>استيراد قايمة أدوية</h2>

      <p className="cfg__hint">
        الزق القايمة هنا — من Excel، أو ملف CSV، أو حتى اسم في كل سطر.
        السيستم بيقرا الأعمدة لوحده وبيوريك النتيجة قبل ما يحفظ.
      </p>

      <div className="row clinic__filters">
        <label>
          <span className="cfg__hint">أو اختار ملف CSV</span>
          <input
            className="input"
            type="file"
            accept=".csv,.tsv,.txt,text/csv,text/plain"
            onChange={async (e) => {
              const file = e.target.files?.[0];
              if (file) setText(await file.text());
            }}
          />
        </label>
      </div>

      <label>
        <span className="cfg__hint">القايمة</span>
        <textarea
          className="input"
          rows={8}
          dir="auto"
          placeholder={'Concor\tكونكور\tبيسوبرولول\tأقراص\t5 مجم\nAugmentin\tأوجمنتين\tأموكسيسيللين\tأقراص\t1 جم'}
          value={text}
          onChange={(e) => setText(e.target.value)}
        />
      </label>

      {parsed.rows.length > 0 ? (
        <>
          <p className="cfg__hint">
            قرينا <strong>{parsed.rows.length}</strong> دوا
            {parsed.ignored > 0 ? ` · ${parsed.ignored} سطر اتجاهل (مفيهوش اسم)` : ''}
            {parsed.hadHeader ? ' · فيه صف عناوين واتجاهل' : ' · مفيش صف عناوين'}
          </p>

          {/* The detected mapping, spelled out. A wrong guess is invisible
              otherwise, and the fix — reordering the columns — is only obvious
              once you can see what was guessed. */}
          <p className="cfg__hint">
            الأعمدة اتقرت كده:{' '}
            {parsed.columns
              .map((c: string) => COLUMN_LABEL[c as keyof typeof COLUMN_LABEL] ?? c)
              .join(' · ')}
          </p>

          <table className="clinic__table">
            <thead>
              <tr>
                <th>الاسم التجاري</th><th>بالعربي</th><th>المادة الفعالة</th>
                <th>الشكل</th><th>التركيز</th>
              </tr>
            </thead>
            <tbody>
              {parsed.rows.slice(0, 8).map((r, i: number) => (
                <tr key={i}>
                  <td><strong>{r.trade_name}</strong></td>
                  <td>{r.trade_name_ar || '—'}</td>
                  <td>{r.generic_ar || '—'}</td>
                  <td>{r.form_ar || '—'}</td>
                  <td className="num" dir="ltr">{r.strength || '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
          {parsed.rows.length > 8 ? (
            <p className="cfg__hint">…و {parsed.rows.length - 8} كمان.</p>
          ) : null}
        </>
      ) : null}

      {result ? <p className="clinic__ok" role="status">{result}</p> : null}

      <div className="row clinic__actions">
        <button
          type="button"
          className="btn btn--brand"
          disabled={busy || parsed.rows.length === 0}
          onClick={async () => {
            setBusy(true);
            setResult(null);
            try {
              const { data, error } = await clinicSupabase()
                .rpc('import_drugs', { p_rows: parsed.rows });
              if (error) throw error;
              const r = data as { added: number; updated: number; skipped: number };
              setResult(
                `اتضاف ${r.added} دوا جديد، واتحدّث ${r.updated}` +
                (r.skipped > 0 ? `، و${r.skipped} اتكرروا أو مفيهمش اسم` : '') + '.'
              );
              setText('');
              await syncCatalog(true).catch(() => {});
              await onDone();
            } catch (e) {
              onError(toArabicError(e));
            } finally {
              setBusy(false);
            }
          }}
        >
          {busy ? 'بيستورد…' : `استورد ${parsed.rows.length || ''} دوا`}
        </button>
        <span className="cfg__hint">
          الدوا الموجود بيتحدّث مش بيتكرر. أقصى عدد ٥٠٠٠ في المرة.
        </span>
      </div>
    </div>
  );
}
