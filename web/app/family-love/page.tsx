'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { hasStoredSession, currentDeviceKind } from '@/lib/family-love/session';

export default function FamilyLoveLanding() {
  const router = useRouter();
  const [checked, setChecked] = useState(false);

  useEffect(() => {
    if (hasStoredSession()) {
      router.replace(currentDeviceKind() === 'child' ? '/family-love/child' : '/family-love/home');
      return;
    }
    setChecked(true);
  }, [router]);

  if (!checked) return null;

  return (
    <div className="fl__shell">
      <div className="fl__bar">
        <span className="fl__brand">عائلتي</span>
      </div>

      <div className="fl__card fl__center">
        <div style={{ fontSize: 40, marginBlockEnd: 12 }}>🚌</div>
        <h1 style={{ marginBlock: '0 8px', fontSize: '1.3rem' }}>متابعة يومية بين الأهل والطفل</h1>
        <p className="fl__muted">مهام ومحطات، تنبيهات، وموقع لحظي — من غير أي تعقيد.</p>
        <Link
          href="/family-love/login"
          className="btn btn--brand"
          style={{ display: 'inline-block', marginBlockStart: 16 }}
        >
          ابدأ كأب أو أم
        </Link>
      </div>

      <div className="fl__card">
        <h2 style={{ marginBlock: '0 8px', fontSize: '1rem' }}>📱 مستخدم آيفون؟</h2>
        <p className="fl__muted">
          افتح الرابط ده في Safari، اضغط زرار المشاركة ⬆️، وبعدين &quot;إضافة إلى الشاشة الرئيسية&quot; —
          هيبقى شغال زي أي تطبيق عادي.
        </p>
      </div>
    </div>
  );
}
