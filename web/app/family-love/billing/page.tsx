'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { hasStoredSession, currentDeviceKind } from '@/lib/family-love/session';
import { familyLoveSupabase } from '@/lib/family-love/supabaseBrowser';
import type { Entitlement } from '@/lib/family-love/types';

const STATUS_LABELS: Record<Entitlement['status'], string> = {
  trialing: 'تجربة مجانية',
  active: 'مفعّل',
  past_due: 'متأخر في الدفع',
  expired: 'التجربة انتهت',
  cancelled: 'ملغي',
};

function daysLeft(iso: string): number {
  const ms = new Date(iso).getTime() - Date.now();
  return Math.max(0, Math.ceil(ms / (1000 * 60 * 60 * 24)));
}

export default function FamilyLoveBillingPage() {
  const router = useRouter();
  const [ready, setReady] = useState(false);
  const [entitlement, setEntitlement] = useState<Entitlement | null>(null);
  const [isTwa, setIsTwa] = useState(false);

  useEffect(() => {
    if (!hasStoredSession() || currentDeviceKind() !== 'parent') {
      router.replace('/family-love/login');
      return;
    }
    setIsTwa(document.referrer.startsWith('android-app://'));
    (async () => {
      const { data } = await familyLoveSupabase().rpc('fl_my_entitlement');
      setEntitlement((data as Entitlement | null) ?? null);
      setReady(true);
    })();
  }, [router]);

  if (!ready) return null;

  return (
    <div className="fl__shell">
      <div className="fl__bar">
        <Link href="/family-love/settings" className="fl__brand" style={{ textDecoration: 'none' }}>
          عائلتي
        </Link>
      </div>

      <h1 style={{ fontSize: '1.1rem', marginBlock: '0 12px' }}>💳 الاشتراك</h1>

      {entitlement && (
        <div className="fl__card">
          <p style={{ fontSize: '1.2rem', fontWeight: 700, margin: 0 }}>{STATUS_LABELS[entitlement.status]}</p>

          {entitlement.status === 'trialing' && entitlement.trial_ends_at && (
            <p className="fl__muted">
              باقي {daysLeft(entitlement.trial_ends_at)} يوم على التجربة المجانية (لحد{' '}
              {new Date(entitlement.trial_ends_at).toLocaleDateString('ar-EG')}).
            </p>
          )}

          {entitlement.status === 'active' && entitlement.current_period_end && (
            <p className="fl__muted">
              الاشتراك متجدد لحد {new Date(entitlement.current_period_end).toLocaleDateString('ar-EG')}.
            </p>
          )}

          {(entitlement.status === 'expired' || entitlement.status === 'past_due') && (
            <p className="fl__error">محتاج تجدد الاشتراك عشان تكمل تستخدم التطبيق.</p>
          )}
        </div>
      )}

      <div className="fl__card">
        <h2 style={{ marginBlock: '0 8px', fontSize: '1rem' }}>الدفع</h2>
        {isTwa ? (
          <p className="fl__muted">الدفع عن طريق Google Play هيتفعّل قريبًا في التحديث الجاي.</p>
        ) : (
          <p className="fl__muted">
            الدفع لمستخدمي آيفون والويب هيتفعّل قريبًا. لو عايز تكمل بعد التجربة المجانية، تابع معانا هنا.
          </p>
        )}
      </div>
    </div>
  );
}
