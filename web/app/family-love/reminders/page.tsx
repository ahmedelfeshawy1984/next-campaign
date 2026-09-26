'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { hasStoredSession, currentDeviceKind } from '@/lib/family-love/session';
import { familyLoveSupabase } from '@/lib/family-love/supabaseBrowser';
import type { ChildProfile } from '@/lib/family-love/types';

interface AlertRow {
  id: string;
  child_profile_id: string | null;
  scheduled_for: string | null;
  fired_at: string | null;
  payload: { message?: string };
}

export default function FamilyLoveRemindersPage() {
  const router = useRouter();
  const [ready, setReady] = useState(false);
  const [children, setChildren] = useState<ChildProfile[]>([]);
  const [reminders, setReminders] = useState<AlertRow[]>([]);
  const [childId, setChildId] = useState('');
  const [when, setWhen] = useState('');
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    const sb = familyLoveSupabase();
    const [{ data: childRows }, { data: alertRows }] = await Promise.all([
      sb.from('child_profiles').select('*').order('created_at'),
      sb.from('alerts').select('*').eq('origin', 'parent_reminder').order('scheduled_for', { ascending: true }),
    ]);
    const list = (childRows ?? []) as ChildProfile[];
    setChildren(list);
    if (!childId && list[0]) setChildId(list[0].id);
    setReminders((alertRows ?? []) as AlertRow[]);
  }, [childId]);

  useEffect(() => {
    if (!hasStoredSession() || currentDeviceKind() !== 'parent') {
      router.replace('/family-love/login');
      return;
    }
    load().finally(() => setReady(true));
    // eslint-disable-next-line react-hooks/exhaustive-deps -- تحميل مرة واحدة بس
  }, [router]);

  async function createReminder(event: React.FormEvent) {
    event.preventDefault();
    if (!when || !message.trim()) {
      setError('لازم تحدد الميعاد والرسالة.');
      return;
    }
    const child = children.find((c) => c.id === childId);
    if (!child) return;
    setBusy(true);
    setError(null);
    try {
      const { error: insertError } = await familyLoveSupabase().from('alerts').insert({
        family_circle_id: child.family_circle_id,
        child_profile_id: child.id,
        origin: 'parent_reminder',
        scheduled_for: new Date(when).toISOString(),
        payload: { message: message.trim() },
      });
      if (insertError) throw insertError;
      setMessage('');
      setWhen('');
      await load();
    } catch {
      setError('التنبيه معرفش يتحفظ، جرب تاني.');
    } finally {
      setBusy(false);
    }
  }

  if (!ready) return null;

  return (
    <div className="fl__shell">
      <div className="fl__bar">
        <Link href="/family-love/home" className="fl__brand" style={{ textDecoration: 'none' }}>
          عائلتي
        </Link>
      </div>

      <h1 style={{ fontSize: '1.1rem', marginBlock: '0 12px' }}>⏰ تنبيه بميعاد</h1>

      <form onSubmit={createReminder} className="fl__card">
        <label htmlFor="fl-rem-child">الطفل</label>
        <select id="fl-rem-child" className="fl__input" value={childId} onChange={(e) => setChildId(e.target.value)}>
          {children.map((child) => (
            <option key={child.id} value={child.id}>
              {child.display_name}
            </option>
          ))}
        </select>

        <label htmlFor="fl-rem-when">الميعاد</label>
        <input
          id="fl-rem-when"
          className="fl__input"
          type="datetime-local"
          value={when}
          onChange={(e) => setWhen(e.target.value)}
        />

        <label htmlFor="fl-rem-msg">الرسالة</label>
        <input
          id="fl-rem-msg"
          className="fl__input"
          placeholder="معاد درس البيانو"
          value={message}
          onChange={(e) => setMessage(e.target.value)}
        />

        {error && <p className="fl__error">{error}</p>}
        <button type="submit" className="btn btn--brand" disabled={busy} style={{ inlineSize: '100%', marginBlockStart: 10 }}>
          احفظ التنبيه
        </button>
      </form>

      <div className="fl__card">
        <h2 style={{ marginBlock: '0 8px', fontSize: '1rem' }}>التنبيهات القادمة</h2>
        {reminders.length === 0 && <p className="fl__muted">مفيش تنبيهات محفوظة.</p>}
        <ul className="fl__list">
          {reminders.map((r) => (
            <li key={r.id}>
              <div style={{ flex: 1 }}>
                <div>{r.payload?.message}</div>
                <div className="fl__muted">
                  {r.scheduled_for ? new Date(r.scheduled_for).toLocaleString('ar-EG') : '—'}
                  {r.fired_at ? ' — اتبعت' : ' — لسه ماجاش'}
                </div>
              </div>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
