'use client';

import { useEffect, useState, use as usePromise } from 'react';
import { useRouter } from 'next/navigation';
import { hasStoredSession, currentDeviceKind } from '@/lib/family-love/session';
import { familyLoveSupabase } from '@/lib/family-love/supabaseBrowser';
import type { RecurrenceRule } from '@/lib/family-love/recurrence.js';

const WEEKDAYS = ['الأحد', 'الاتنين', 'التلات', 'الأربع', 'الخميس', 'الجمعة', 'السبت'];

interface TaskRow {
  id: string;
  family_circle_id: string;
  title: string;
  recurrence_rule: RecurrenceRule;
  is_active: boolean;
}

export default function EditTaskPage({ params }: { params: Promise<{ taskId: string }> }) {
  const { taskId } = usePromise(params);
  const router = useRouter();
  const [ready, setReady] = useState(false);
  const [title, setTitle] = useState('');
  const [stations, setStations] = useState<string[]>([]);
  const [isActive, setIsActive] = useState(true);
  const [kind, setKind] = useState<RecurrenceRule['kind']>('daily');
  const [weekdays, setWeekdays] = useState<number[]>([]);
  const [dayOfMonth, setDayOfMonth] = useState(1);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!hasStoredSession() || currentDeviceKind() !== 'parent') {
      router.replace('/family-love/login');
      return;
    }
    (async () => {
      const sb = familyLoveSupabase();
      const [{ data: task }, { data: stationRows }] = await Promise.all([
        sb.from('tasks').select('*').eq('id', taskId).maybeSingle<TaskRow>(),
        sb.from('stations').select('title').eq('task_id', taskId).order('order_index'),
      ]);
      if (task) {
        setTitle(task.title);
        setIsActive(task.is_active);
        const rule = task.recurrence_rule;
        setKind(rule.kind);
        if (rule.kind === 'weekly') setWeekdays(rule.weekdays);
        if (rule.kind === 'monthly') setDayOfMonth(rule.day_of_month);
      }
      setStations(((stationRows ?? []) as Array<{ title: string }>).map((s) => s.title));
      setReady(true);
    })();
  }, [router, taskId]);

  function toggleWeekday(day: number) {
    setWeekdays((prev) => (prev.includes(day) ? prev.filter((d) => d !== day) : [...prev, day].sort()));
  }

  function recurrenceRule(): RecurrenceRule {
    if (kind === 'weekly') return { kind: 'weekly', weekdays };
    if (kind === 'monthly') return { kind: 'monthly', day_of_month: dayOfMonth };
    if (kind === 'once') return { kind: 'once', date: new Date().toISOString().slice(0, 10) };
    return { kind: 'daily' };
  }

  async function save(event: React.FormEvent) {
    event.preventDefault();
    const cleanStations = stations.map((s) => s.trim()).filter(Boolean);
    if (!title.trim() || cleanStations.length === 0) {
      setError('لازم عنوان ومحطة واحدة على الأقل.');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const sb = familyLoveSupabase();
      const { error: taskError } = await sb
        .from('tasks')
        .update({ title: title.trim(), recurrence_rule: recurrenceRule(), is_active: isActive })
        .eq('id', taskId);
      if (taskError) throw taskError;

      await sb.from('stations').delete().eq('task_id', taskId);
      const { error: stationsError } = await sb
        .from('stations')
        .insert(cleanStations.map((stationTitle, index) => ({ task_id: taskId, order_index: index, title: stationTitle })));
      if (stationsError) throw stationsError;

      router.replace('/family-love/home');
    } catch {
      setError('حصلت مشكلة في الحفظ، جرب تاني.');
    } finally {
      setBusy(false);
    }
  }

  async function remove() {
    setBusy(true);
    try {
      await familyLoveSupabase().from('tasks').delete().eq('id', taskId);
      router.replace('/family-love/home');
    } finally {
      setBusy(false);
    }
  }

  if (!ready) return null;

  return (
    <div className="fl__shell">
      <div className="fl__bar">
        <span className="fl__brand">تعديل المهمة</span>
      </div>

      <form onSubmit={save} className="fl__card">
        <label htmlFor="fl-etask-title">عنوان المهمة</label>
        <input id="fl-etask-title" className="fl__input" value={title} onChange={(e) => setTitle(e.target.value)} />

        <label>المحطات</label>
        {stations.map((station, index) => (
          <div key={index} style={{ display: 'flex', gap: 6, marginBlockEnd: 8 }}>
            <input
              className="fl__input"
              value={station}
              onChange={(e) => setStations((prev) => prev.map((s, i) => (i === index ? e.target.value : s)))}
            />
            <button
              type="button"
              className="btn btn--ghost btn--sm"
              onClick={() => setStations((prev) => prev.filter((_, i) => i !== index))}
            >
              ✕
            </button>
          </div>
        ))}
        <button type="button" className="btn btn--ghost btn--sm" onClick={() => setStations((prev) => [...prev, ''])}>
          ➕ إضافة محطة
        </button>

        <label htmlFor="fl-etask-kind" style={{ marginBlockStart: 16 }}>
          التكرار
        </label>
        <select id="fl-etask-kind" className="fl__input" value={kind} onChange={(e) => setKind(e.target.value as RecurrenceRule['kind'])}>
          <option value="daily">كل يوم</option>
          <option value="weekly">أيام معينة كل أسبوع</option>
          <option value="monthly">يوم معين كل شهر</option>
          <option value="once">مرة واحدة بس</option>
        </select>

        {kind === 'weekly' && (
          <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginBlockStart: 8 }}>
            {WEEKDAYS.map((label, day) => (
              <button
                key={day}
                type="button"
                className={weekdays.includes(day) ? 'btn btn--brand btn--sm' : 'btn btn--ghost btn--sm'}
                onClick={() => toggleWeekday(day)}
              >
                {label}
              </button>
            ))}
          </div>
        )}

        {kind === 'monthly' && (
          <input
            type="number"
            min={1}
            max={31}
            className="fl__input"
            style={{ marginBlockStart: 8 }}
            value={dayOfMonth}
            onChange={(e) => setDayOfMonth(Number(e.target.value))}
          />
        )}

        <label style={{ display: 'flex', alignItems: 'center', gap: 8, marginBlockStart: 12 }}>
          <input type="checkbox" checked={isActive} onChange={(e) => setIsActive(e.target.checked)} />
          المهمة نشطة
        </label>

        {error && <p className="fl__error">{error}</p>}
        <button type="submit" className="btn btn--brand" disabled={busy} style={{ inlineSize: '100%', marginBlockStart: 16 }}>
          {busy ? 'جاري الحفظ...' : 'احفظ التعديلات'}
        </button>
        <button type="button" className="btn btn--ghost" disabled={busy} onClick={remove} style={{ inlineSize: '100%', marginBlockStart: 8 }}>
          🗑️ احذف المهمة
        </button>
      </form>
    </div>
  );
}
