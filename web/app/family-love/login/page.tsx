'use client';

import { useState, type FormEvent } from 'react';
import { useRouter } from 'next/navigation';
import { saveSession } from '@/lib/family-love/session';

type Step = 'phone' | 'code';

export default function FamilyLoveLoginPage() {
  const router = useRouter();
  const [step, setStep] = useState<Step>('phone');
  const [phone, setPhone] = useState('');
  const [code, setCode] = useState('');
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
      setError('رقم التليفون مش صحيح — لازم يكون رقم موبايل مصري.');
    } finally {
      setBusy(false);
    }
  }

  async function verifyCode(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch('/api/family-love/otp/verify', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ phone, code }),
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
      setError('الكود مش صحيح، جرب تاني.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="fl__shell">
      <div className="fl__bar">
        <span className="fl__brand">عائلتي</span>
      </div>

      <div className="fl__card">
        {step === 'phone' ? (
          <form onSubmit={requestCode}>
            <h1 style={{ marginBlock: '0 4px', fontSize: '1.1rem' }}>سجّل برقم تليفونك</h1>
            <p className="fl__muted">هنبعتلك كود تأكيد، من غير أي باسورد.</p>
            <label htmlFor="fl-phone">رقم الموبايل</label>
            <input
              id="fl-phone"
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
          <form onSubmit={verifyCode}>
            <h1 style={{ marginBlock: '0 4px', fontSize: '1.1rem' }}>اكتب الكود</h1>
            <p className="fl__muted">اتبعت كود لرقم {phone}.</p>
            <label htmlFor="fl-code">كود التأكيد</label>
            <input
              id="fl-code"
              className="fl__input"
              type="text"
              inputMode="numeric"
              placeholder="000000"
              value={code}
              onChange={(e) => setCode(e.target.value)}
              required
            />
            {error && <p className="fl__error">{error}</p>}
            <button type="submit" className="btn btn--brand" disabled={busy} style={{ inlineSize: '100%', marginBlockStart: 12 }}>
              {busy ? 'جاري التأكيد...' : 'ادخل'}
            </button>
            <button
              type="button"
              className="btn btn--ghost"
              onClick={() => setStep('phone')}
              style={{ inlineSize: '100%', marginBlockStart: 8 }}
            >
              غيّر الرقم
            </button>
          </form>
        )}
      </div>
    </div>
  );
}
