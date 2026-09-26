'use client';

import { Suspense, useEffect, useState, type FormEvent } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { hasStoredSession, currentDeviceKind } from '@/lib/family-love/session';
import { familyLoveSupabase } from '@/lib/family-love/supabaseBrowser';
import type { ChildProfile } from '@/lib/family-love/types';
import type { RecurrenceRule } from '@/lib/family-love/recurrence.js';

const WEEKDAYS = ['الأحد', 'الاتنين', 'التلات', 'الأربع', 'الخميس', 'الجمعة', 'السبت'];

function NewTaskForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [ready, setReady] = useState(false);
  const [children, setChildren] = useState<ChildProfile[]>([]);
  const [childId, setChildId] = useState(searchParams.get('child') ?? '');
  const [title, setTitle] = useState('');
  const [stations, setStations] = useState<string[]>(['', '']);
  const [kind, setKind] = useState<RecurrenceRule['kind']>('daily');
  const [weekdays, setWeekdays] = useState<number[]>([0, 1, 2, 3, 4]);
  const [dayOfMonth, setDayOfMonth] = useState(1);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!hasStoredSession() || currentDeviceKind() !== 'parent') {
      router.replace('/family-love/login');
      return;
    }
    familyLoveSupabase()
      .from('child_profiles')
      .select('*')
      .then(({ data }) => {
        const list = (data ?? []) as ChildProfile[];
        setChildren(list);
        if (!childId && list[0]) setChildId(list[0].id);
        setReady(true);
      });
    // eslint-disable-next-line react-hooks/exhaustive-deps -- تشغيل مرة واحدة بس عند التحميل
  }, [router]);

  function toggleWeekday(day: number) {
    setWeekdays((prev) => (prev.includes(day) ? prev.filter((d) => d !== day) : [...prev, day].sort()));
  }

  function recurrenceRule(): RecurrenceRule {
    if (kind === 'weekly') return { kind: 'weekly', weekdays };
    if (kind === 'monthly') return { kind: 'monthly', day_of_month: dayOfMonth };
    if (kind === 'once') return { kind: 'once', date: new Date().toISOString().slice(0, 10) };
    return { kind: 'daily' };
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    const cleanStations = stations.map((s) => s.trim()).filter(Boolean);
    if (!childId || !title.trim() || cleanStations.length === 0) {
      setError('لازم تختار طفل، وعنوان مهمة، ومحطة واحدة على الأقل.');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const sb = familyLoveSupabase();
      const { data: task, error: taskError } = await sb
        .from('tasks')
        .insert({
          family_circle_id: (children.find((c) => c.id === childId) as ChildProfile).family_circle_id,
          child_profile_id: childId,
          title: title.trim(),
          recurrence_rule: recurrenceRule(),
        })
        .select('id')
        .single<{ id: string }>();
      if (taskError || !task) throw taskError;

      const rows = cleanStations.map((stationTitle, index) => ({
        task_id: task.id,
        order_index: index,
        title: stationTitle,
      }));
      const { error: stationsError } = await sb.from('stations').insert(rows);
      if (stationsError) throw stationsError;

      router.replace('/family-love/home');
    } catch {
      setError('حصلت مشكلة في حفظ المهمة، جرب تاني.');
    } finally {
      setBusy(false);
    }
  }

  if (!ready) return null;

  return (
    <div className="fl__shell">
      <div className="fl__bar">
        <span className="fl__brand">مهمة جديدة</span>
      </div>

      <form onSubmit={submit} className="fl__card">
        <label htmlFor="fl-task-child">الطفل</label>
        <select id="fl-task-child" className="fl__input" value={childId} onChange={(e) => setChildId(e.target.value)}>
          {children.map((child) => (
            <option key={child.id} value={child.id}>
              {child.display_name}
            </option>
          ))}
        </select>

        <label htmlFor="fl-task-title">عنوان المهمة</label>
        <input
          id="fl-task-title"
          className="fl__input"
          placeholder="رحلة المدرسة"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
        />

        <label>المحطات</label>
        {stations.map((station, index) => (
          <input
            key={index}
            className="fl__input"
            style={{ marginBlockEnd: 8 }}
            placeholder={`المحطة ${index + 1}`}
            value={station}
            onChange={(e) => setStations((prev) => prev.map((s, i) => (i === index ? e.target.value : s)))}
          />
        ))}
        <button
          type="button"
          className="btn btn--ghost btn--sm"
          onClick={() => setStations((prev) => [...prev, ''])}
        >
          ➕ إضافة محطة
        </button>

        <label htmlFor="fl-task-kind" style={{ marginBlockStart: 16 }}>
          التكرار
        </label>
        <select id="fl-task-kind" className="fl__input" value={kind} onChange={(e) => setKind(e.target.value as RecurrenceRule['kind'])}>
          <option value="daily">كل يوم</option>
          <option value="weekly">أيام معينة كل أسبوع</option>
          <option value="monthly">يوم معين كل شهر</option>
          <option value="once">مرة واحدة بس النهاردة</option>
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

        {error && <p className="fl__error">{error}</p>}
        <button type="submit" className="btn btn--brand" disabled={busy} style={{ inlineSize: '100%', marginBlockStart: 16 }}>
          {busy ? 'جاري الحفظ...' : 'حفظ المهمة'}
        </button>
      </form>
    </div>
  );
}

export default function NewTaskPage() {
  return (
    <Suspense fallback={null}>
      <NewTaskForm />
    </Suspense>
  );
}
