'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { hasStoredSession, currentDeviceKind, clearSession } from '@/lib/family-love/session';
import { familyLoveSupabase } from '@/lib/family-love/supabaseBrowser';
import { qrCodeUrl } from '@/lib/family-love/qr';
import BusStrip from '@/components/family-love/BusStrip';
import type { BoardTask, ChildProfile } from '@/lib/family-love/types';

interface PairingInfo {
  code: string;
  link: string;
}

export default function FamilyLoveHomePage() {
  const router = useRouter();
  const [ready, setReady] = useState(false);
  const [children, setChildren] = useState<ChildProfile[]>([]);
  const [boards, setBoards] = useState<Record<string, BoardTask[]>>({});
  const [newChildName, setNewChildName] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pairing, setPairing] = useState<Record<string, PairingInfo>>({});

  const loadChildren = useCallback(async () => {
    const sb = familyLoveSupabase();
    const { data, error: fetchError } = await sb.from('child_profiles').select('*').order('created_at');
    if (fetchError) {
      setError('حصلت مشكلة في تحميل بيانات الأطفال.');
      return;
    }
    const list = (data ?? []) as ChildProfile[];
    setChildren(list);

    const entries = await Promise.all(
      list.map(async (child) => {
        const { data: board } = await sb.rpc('fl_today_board', { p_child_profile_id: child.id });
        return [child.id, (board as BoardTask[]) ?? []] as const;
      })
    );
    setBoards(Object.fromEntries(entries));
  }, []);

  useEffect(() => {
    if (!hasStoredSession() || currentDeviceKind() !== 'parent') {
      router.replace('/family-love/login');
      return;
    }
    loadChildren().finally(() => setReady(true));
  }, [router, loadChildren]);

  async function addChild(event: React.FormEvent) {
    event.preventDefault();
    if (!newChildName.trim()) return;
    setBusy(true);
    setError(null);
    try {
      const sb = familyLoveSupabase();
      const { error: rpcError } = await sb.rpc('fl_create_child_profile', {
        p_display_name: newChildName.trim(),
        p_avatar_url: null,
      });
      if (rpcError) throw rpcError;
      setNewChildName('');
      await loadChildren();
    } catch {
      setError('معرفناش نضيف الطفل، جرب تاني.');
    } finally {
      setBusy(false);
    }
  }

  async function createPairingLink(childId: string) {
    setBusy(true);
    setError(null);
    try {
      const sb = familyLoveSupabase();
      const { data, error: rpcError } = await sb
        .rpc('fl_create_pairing_token', { p_child_profile_id: childId })
        .single<{ code: string }>();
      if (rpcError || !data) throw rpcError;
      const link = `${window.location.origin}/family-love/pair?code=${data.code}`;
      setPairing((prev) => ({ ...prev, [childId]: { code: data.code, link } }));
    } catch {
      setError('معرفناش ننشئ كود ربط دلوقتي، جرب تاني.');
    } finally {
      setBusy(false);
    }
  }

  function signOut() {
    clearSession();
    router.replace('/family-love');
  }

  if (!ready) return null;

  return (
    <div className="fl__shell">
      <div className="fl__bar">
        <span className="fl__brand">عائلتي</span>
        <button type="button" className="btn btn--ghost btn--sm" onClick={signOut}>
          خروج
        </button>
      </div>

      {error && <p className="fl__error">{error}</p>}

      {children.length === 0 && (
        <div className="fl__card fl__center">
          <p className="fl__muted">لسه معندكش أطفال مضافين.</p>
        </div>
      )}

      {children.map((child) => {
        const board = boards[child.id] ?? [];
        const activeTask = board[0];
        const info = pairing[child.id];
        return (
          <div className="fl__card" key={child.id}>
            <div className="fl__child-head">
              <div className="fl__avatar">🧒</div>
              <div>
                <div style={{ fontWeight: 700 }}>{child.display_name}</div>
                {activeTask && <div className="fl__muted">{activeTask.title}</div>}
              </div>
            </div>

            {activeTask ? (
              <BusStrip task={activeTask} />
            ) : (
              <p className="fl__muted">مفيش مهمة مجدولة النهاردة لـ{child.display_name}.</p>
            )}

            <div style={{ display: 'flex', gap: 8, marginBlockStart: 16, flexWrap: 'wrap' }}>
              <Link href={`/family-love/tasks/new?child=${child.id}`} className="btn btn--brand btn--sm">
                مهمة جديدة
              </Link>
              <button type="button" className="btn btn--ghost btn--sm" onClick={() => createPairingLink(child.id)} disabled={busy}>
                ربط جهاز الطفل
              </button>
            </div>

            {info && (
              <div className="fl__card" style={{ marginBlockStart: 12, background: 'var(--surface)' }}>
                <p className="fl__muted" style={{ marginBlock: 0 }}>
                  كود الربط (صالح ١٥ دقيقة):
                </p>
                <p style={{ fontSize: '1.4rem', fontWeight: 800, letterSpacing: '0.2em', margin: '4px 0' }}>{info.code}</p>
                {/* eslint-disable-next-line @next/next/no-img-element -- صورة QR من خدمة خارجية، مش asset محلي */}
                <img src={qrCodeUrl(info.link)} alt="كود QR لربط جهاز الطفل" width={160} height={160} />
                <p className="fl__muted" style={{ wordBreak: 'break-all' }}>{info.link}</p>
              </div>
            )}
          </div>
        );
      })}

      <form onSubmit={addChild} className="fl__card">
        <label htmlFor="fl-child-name">إضافة طفل</label>
        <input
          id="fl-child-name"
          className="fl__input"
          placeholder="اسم الطفل"
          value={newChildName}
          onChange={(e) => setNewChildName(e.target.value)}
        />
        <button type="submit" className="btn btn--brand" disabled={busy} style={{ inlineSize: '100%', marginBlockStart: 10 }}>
          إضافة
        </button>
      </form>

      <Link href="/family-love/circle" className="btn btn--ghost" style={{ inlineSize: '100%', display: 'block', textAlign: 'center', marginBlockEnd: 10 }}>
        👪 أفراد العيلة
      </Link>

      <div className="fl__ad">
        <div style={{ blockSize: 84, display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'var(--fl-tint)', color: 'var(--fl)', fontWeight: 700, fontSize: '0.85rem' }}>
          [مساحة إعلان]
        </div>
        <span className="fl__ad-tag">إعلان</span>
      </div>
    </div>
  );
}
