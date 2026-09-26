'use client';

import { Suspense, useState, type FormEvent } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { saveSession } from '@/lib/family-love/session';

type Step = 'phone' | 'code';

function JoinForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [invite] = useState(searchParams.get('code') ?? '');
  const [step, setStep] = useState<Step>('phone');
  const [phone, setPhone] = useState('');
  const [fullName, setFullName] = useState('');
  const [otpCode, setOtpCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function requestCode(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch('/api/family-love/otp/request', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ phone }),
      });
      if (!res.ok) throw new Error();
      setStep('code');
    } catch {
      setError('رقم التليفون مش صحيح.');
    } finally {
      setBusy(false);
    }
  }

  async function join(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch('/api/family-love/members/join', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ code: invite, phone, otpCode, fullName }),
      });
      if (!res.ok) throw new Error();
      const data = (await res.json()) as { accessToken: string; refreshToken: string; expiresIn: number };
      saveSession({
        refreshToken: data.refreshToken,
        kind: 'parent',
        accessToken: data.accessToken,
        expiresIn: data.expiresIn,
      });
      router.replace('/family-love/home');
    } catch {
      setError('كود الدعوة أو كود التأكيد مش صحيح.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="fl__shell">
      <div className="fl__bar">
        <span className="fl__brand">عائلتي</span>
      </div>

      <div className="fl__card fl__center">
        <div style={{ fontSize: 40, marginBlockEnd: 8 }}>👪</div>
        <h1 style={{ marginBlock: '0 4px', fontSize: '1.2rem' }}>انضم لعيلتك</h1>
        <p className="fl__muted">حد من عيلتك دعاك تنضم لمتابعة الأطفال معاه.</p>
      </div>

      <div className="fl__card">
        {step === 'phone' ? (
          <form onSubmit={requestCode}>
            <label htmlFor="fl-join-name">اسمك</label>
            <input id="fl-join-name" className="fl__input" value={fullName} onChange={(e) => setFullName(e.target.value)} />
            <label htmlFor="fl-join-phone">رقم موبايلك</label>
            <input
              id="fl-join-phone"
              className="fl__input"
              type="tel"
              inputMode="numeric"
              placeholder="01xxxxxxxxx"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              required
            />
            {error && <p className="fl__error">{error}</p>}
            <button type="submit" className="btn btn--brand" disabled={busy} style={{ inlineSize: '100%', marginBlockStart: 12 }}>
              {busy ? 'جاري الإرسال...' : 'ابعتلي الكود'}
            </button>
          </form>
        ) : (
          <form onSubmit={join}>
            <label htmlFor="fl-join-otp">كود التأكيد</label>
            <input
              id="fl-join-otp"
              className="fl__input"
              type="text"
              inputMode="numeric"
              value={otpCode}
              onChange={(e) => setOtpCode(e.target.value)}
              required
            />
            {error && <p className="fl__error">{error}</p>}
            <button type="submit" className="btn btn--brand" disabled={busy} style={{ inlineSize: '100%', marginBlockStart: 12 }}>
              {busy ? 'جاري الدخول...' : 'انضم للعيلة'}
            </button>
          </form>
        )}
      </div>
    </div>
  );
}

export default function FamilyLoveJoinPage() {
  return (
    <Suspense fallback={null}>
      <JoinForm />
    </Suspense>
  );
}
