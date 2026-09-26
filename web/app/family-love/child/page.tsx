'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { hasStoredSession, currentDeviceKind, getAccessToken } from '@/lib/family-love/session';
import { familyLoveSupabase } from '@/lib/family-love/supabaseBrowser';
import { familyLoveEnv, familyLovePushIsConfigured } from '@/lib/family-love/env';
import { setupPushNotifications } from '@/lib/family-love/pushClient';
import BusStrip from '@/components/family-love/BusStrip';
import type { BoardTask } from '@/lib/family-love/types';

async function postToFamilyLoveApi(path: string, body: unknown): Promise<boolean> {
  const token = await getAccessToken();
  const res = await fetch(path, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(body),
  });
  return res.ok;
}

export default function FamilyLoveChildPage() {
  const router = useRouter();
  const [ready, setReady] = useState(false);
  const [board, setBoard] = useState<BoardTask[]>([]);
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<string | null>(null);

  const load = useCallback(async () => {
    const { data } = await familyLoveSupabase().rpc('fl_today_board');
    setBoard((data as BoardTask[]) ?? []);
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

  async function sendSos() {
    setBusy(true);
    setNote(null);
    const ok = await postToFamilyLoveApi('/api/family-love/child/sos', {});
    setNote(ok ? 'اتبعت طلب اتصال لماما 📞' : 'حصلت مشكلة، جرب تاني.');
    setBusy(false);
  }

  async function sendTrouble() {
    setBusy(true);
    setNote(null);
    const ok = await postToFamilyLoveApi('/api/family-love/child/status', { eventKey: 'battery_low' });
    setNote(ok ? 'اتبعت رسالة إن عندك مشكلة في الموبايل 🔋' : 'حصلت مشكلة، جرب تاني.');
    setBusy(false);
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
        const ok = await postToFamilyLoveApi('/api/family-love/child/location', {
          lat: position.coords.latitude,
          lng: position.coords.longitude,
          accuracy: position.coords.accuracy,
        });
        setNote(ok ? 'اتبعت موقعك، متقلقيش! 📍' : 'حصلت مشكلة، جرب تاني.');
        setBusy(false);
      },
      () => {
        setNote('معرفناش نوصل لموقعك — سماح الوصول للموقع من إعدادات الجهاز.');
        setBusy(false);
      }
    );
  }

  async function enableNotifications() {
    if (!familyLovePushIsConfigured) return;
    const result = await setupPushNotifications(familyLoveEnv.vapidPublicKey);
    if (result === 'subscribed') setNote('التنبيهات شغالة دلوقتي 🔔');
    else if (result === 'not_installed') setNote('لازم تضيف التطبيق للشاشة الرئيسية الأول عشان التنبيهات تشتغل.');
    else if (result === 'denied') setNote('لازم تسمح بالإشعارات من إعدادات الجهاز.');
  }

  if (!ready) return null;

  const activeTask = board.find((t) => t.status !== 'done') ?? board[0];

  return (
    <div className="fl__shell">
      <div className="fl__bar">
        <span className="fl__brand">يلا بينا! 👋</span>
        {familyLovePushIsConfigured && (
          <button type="button" className="btn btn--ghost btn--sm" onClick={enableNotifications}>
            🔔
          </button>
        )}
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
        <button type="button" className="fl__action fl__action--sos" disabled={busy} onClick={sendSos}>
          <span className="fl__action-icon">📞</span>
          <span>نبّهي ماما</span>
        </button>
        <button type="button" className="fl__action fl__action--location" disabled={busy} onClick={sendLocation}>
          <span className="fl__action-icon">📍</span>
          <span>ابعت موقعي</span>
        </button>
        <button type="button" className="fl__action fl__action--trouble" disabled={busy} onClick={sendTrouble}>
          <span className="fl__action-icon">🔋</span>
          <span>عندي مشكلة</span>
        </button>
      </div>
    </div>
  );
}
