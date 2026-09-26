'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { hasStoredSession, currentDeviceKind } from '@/lib/family-love/session';
import { familyLoveSupabase } from '@/lib/family-love/supabaseBrowser';
import BusStrip from '@/components/family-love/BusStrip';
import type { BoardTask } from '@/lib/family-love/types';

export default function FamilyLoveChildPage() {
  const router = useRouter();
  const [ready, setReady] = useState(false);
  const [board, setBoard] = useState<BoardTask[]>([]);
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<string | null>(null);
  const [circleId, setCircleId] = useState<string | null>(null);
  const [childId, setChildId] = useState<string | null>(null);

  const load = useCallback(async () => {
    const sb = familyLoveSupabase();
    const { data } = await sb.rpc('fl_today_board');
    setBoard((data as BoardTask[]) ?? []);

    // محتاجين family_circle_id/child_profile_id عشان ندخّل صف في location_pings
    // و alerts مباشرة — الجهاز شايف صف واحد بس بحكم RLS (بتاعه هو).
    const { data: mine } = await sb.from('child_profiles').select('id, family_circle_id').limit(1).maybeSingle();
    if (mine) {
      setChildId((mine as { id: string }).id);
      setCircleId((mine as { family_circle_id: string }).family_circle_id);
    }
  }, []);

  useEffect(() => {
    if (!hasStoredSession() || currentDeviceKind() !== 'child') {
      router.replace('/family-love/pair');
      return;
    }
    load().finally(() => setReady(true));
  }, [router, load]);

  async function advance(occurrenceId: string) {
    setBusy(true);
    try {
      await familyLoveSupabase().rpc('fl_advance_station', { p_occurrence_id: occurrenceId });
      await load();
    } finally {
      setBusy(false);
    }
  }

  async function sendAlert(origin: 'child_sos' | 'child_status', payload: Record<string, unknown>, message: string) {
    if (!circleId) return;
    setBusy(true);
    setNote(null);
    try {
      await familyLoveSupabase()
        .from('alerts')
        .insert({ family_circle_id: circleId, child_profile_id: childId, origin, payload });
      setNote(message);
    } catch {
      setNote('حصلت مشكلة، جرب تاني.');
    } finally {
      setBusy(false);
    }
  }

  function sendLocation() {
    if (!('geolocation' in navigator)) {
      setNote('الموقع مش متاح على الجهاز ده.');
      return;
    }
    setBusy(true);
    setNote(null);
    navigator.geolocation.getCurrentPosition(
      async (position) => {
        try {
          if (circleId && childId) {
            await familyLoveSupabase().from('location_pings').insert({
              family_circle_id: circleId,
              child_profile_id: childId,
              lat: position.coords.latitude,
              lng: position.coords.longitude,
              accuracy_m: position.coords.accuracy,
            });
          }
          setNote('اتبعت موقعك، متقلقيش! 📍');
        } finally {
          setBusy(false);
        }
      },
      () => {
        setNote('معرفناش نوصل لموقعك — سماح الوصول للموقع من إعدادات الجهاز.');
        setBusy(false);
      }
    );
  }

  if (!ready) return null;

  const activeTask = board.find((t) => t.status !== 'done') ?? board[0];

  return (
    <div className="fl__shell">
      <div className="fl__bar">
        <span className="fl__brand">يلا بينا! 👋</span>
      </div>

      {note && (
        <div className="fl__now" style={{ marginBlockEnd: 16 }}>
          {note}
        </div>
      )}

      {activeTask ? (
        <div className="fl__card">
          <h1 style={{ marginBlock: '0 12px', fontSize: '1.1rem' }}>{activeTask.title}</h1>
          <BusStrip task={activeTask} />
          <button
            type="button"
            className="fl__advance"
            style={{ marginBlockStart: 18 }}
            disabled={busy || activeTask.status === 'done'}
            onClick={() => advance(activeTask.occurrence_id)}
          >
            {activeTask.status === 'done' ? '🎉 وصلت! أحسنت' : '✅ خلصت المحطة دي'}
          </button>
        </div>
      ) : (
        <div className="fl__card fl__center">
          <p className="fl__muted">مفيش مهمة النهاردة.</p>
        </div>
      )}

      <div className="fl__actions">
        <button type="button" className="fl__action fl__action--sos" disabled={busy} onClick={() => sendAlert('child_sos', {}, 'اتبعت طلب اتصال لماما 📞')}>
          <span className="fl__action-icon">📞</span>
          <span>نبّهي ماما</span>
        </button>
        <button type="button" className="fl__action fl__action--location" disabled={busy} onClick={sendLocation}>
          <span className="fl__action-icon">📍</span>
          <span>ابعت موقعي</span>
        </button>
        <button
          type="button"
          className="fl__action fl__action--trouble"
          disabled={busy}
          onClick={() => sendAlert('child_status', { kind: 'trouble' }, 'اتبعت رسالة إن عندك مشكلة في الموبايل 🔋')}
        >
          <span className="fl__action-icon">🔋</span>
          <span>عندي مشكلة</span>
        </button>
      </div>
    </div>
  );
}
