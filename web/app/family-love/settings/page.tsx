'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { hasStoredSession, currentDeviceKind, clearSession } from '@/lib/family-love/session';
import { familyLoveSupabase } from '@/lib/family-love/supabaseBrowser';
import type { DeviceKind, Entitlement } from '@/lib/family-love/types';

interface DeviceRow {
  id: string;
  kind: DeviceKind;
  label: string;
  created_at: string;
  last_seen_at: string;
  revoked_at: string | null;
}

const STATUS_LABELS: Record<Entitlement['status'], string> = {
  trialing: 'تجربة مجانية',
  active: 'مفعّل',
  past_due: 'متأخر في الدفع',
  expired: 'منتهي',
  cancelled: 'ملغي',
};

export default function FamilyLoveSettingsPage() {
  const router = useRouter();
  const [ready, setReady] = useState(false);
  const [entitlement, setEntitlement] = useState<Entitlement | null>(null);
  const [devices, setDevices] = useState<DeviceRow[]>([]);
  const [busyId, setBusyId] = useState<string | null>(null);

  const load = useCallback(async () => {
    const sb = familyLoveSupabase();
    const [{ data: ent }, { data: deviceRows }] = await Promise.all([
      sb.rpc('fl_my_entitlement'),
      sb.rpc('fl_my_circle_devices'),
    ]);
    setEntitlement((ent as Entitlement | null) ?? null);
    setDevices((deviceRows ?? []) as DeviceRow[]);
  }, []);

  useEffect(() => {
    if (!hasStoredSession() || currentDeviceKind() !== 'parent') {
      router.replace('/family-love/login');
      return;
    }
    load().finally(() => setReady(true));
  }, [router, load]);

  async function revoke(deviceId: string) {
    setBusyId(deviceId);
    try {
      await familyLoveSupabase().rpc('fl_revoke_device', { p_device_id: deviceId });
      await load();
    } finally {
      setBusyId(null);
    }
  }

  function signOut() {
    clearSession();
    router.replace('/family-love');
  }

  if (!ready) return null;

  const trialEndsAt = entitlement?.trial_ends_at ? new Date(entitlement.trial_ends_at) : null;

  return (
    <div className="fl__shell">
      <div className="fl__bar">
        <Link href="/family-love/home" className="fl__brand" style={{ textDecoration: 'none' }}>
          عائلتي
        </Link>
      </div>

      <h1 style={{ fontSize: '1.1rem', marginBlock: '0 12px' }}>⚙️ الإعدادات</h1>

      {entitlement && (
        <div className="fl__card">
          <h2 style={{ marginBlock: '0 8px', fontSize: '1rem' }}>الاشتراك</h2>
          <p style={{ margin: 0 }}>{STATUS_LABELS[entitlement.status]}</p>
          {entitlement.status === 'trialing' && trialEndsAt && (
            <p className="fl__muted">التجربة المجانية بتخلص في {trialEndsAt.toLocaleDateString('ar-EG')}</p>
          )}
          <Link href="/family-love/billing" className="btn btn--ghost btn--sm" style={{ marginBlockStart: 8, display: 'inline-block' }}>
            تفاصيل الاشتراك
          </Link>
        </div>
      )}

      <div className="fl__card">
        <h2 style={{ marginBlock: '0 8px', fontSize: '1rem' }}>الأجهزة المرتبطة</h2>
        {devices.length === 0 && <p className="fl__muted">مفيش أجهزة.</p>}
        <ul className="fl__list">
          {devices.map((d) => (
            <li key={d.id}>
              <div style={{ flex: 1 }}>
                <div style={{ fontWeight: 700 }}>
                  {d.kind === 'child' ? '🧒' : '👤'} {d.label}
                </div>
                <div className="fl__muted">آخر ظهور: {new Date(d.last_seen_at).toLocaleString('ar-EG')}</div>
              </div>
              <button
                type="button"
                className="btn btn--ghost btn--sm"
                disabled={busyId === d.id}
                onClick={() => revoke(d.id)}
              >
                افصل
              </button>
            </li>
          ))}
        </ul>
      </div>

      <button type="button" className="btn btn--ghost" style={{ inlineSize: '100%' }} onClick={signOut}>
        خروج من الحساب
      </button>
    </div>
  );
}
