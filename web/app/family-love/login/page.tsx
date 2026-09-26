'use client';

import { useState, type FormEvent } from 'react';
import { useRouter } from 'next/navigation';
import { saveSession } from '@/lib/family-love/session';

export default function FamilyLoveLoginPage() {
  const router = useRouter();
  const [fullName, setFullName] = useState('');
  const [phone, setPhone] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch('/api/family-love/auth/password', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ phone, password, fullName }),
      });
      if (!res.ok) {
        const data = (await res.json().catch(() => null)) as { error?: string } | null;
        if (data?.error === 'WRONG_PASSWORD') setError('الباسورد غلط.');
        else setError('رقم التليفون أو الباسورد مش صحيحين — الباسورد لازم يكون ٦ حروف/أرقام على الأقل.');
        return;
      }
      const data = (await res.json()) as { accessToken: string; refreshToken: string; expiresIn: number };
      saveSession({
        refreshToken: data.refreshToken,
        kind: 'parent',
        accessToken: data.accessToken,
        expiresIn: data.expiresIn,
      });
      router.replace('/family-love/home');
    } catch {
      setError('حصلت مشكلة، جرب تاني.');
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
        <form onSubmit={submit}>
          <h1 style={{ marginBlock: '0 4px', fontSize: '1.1rem' }}>دخول أو تسجيل</h1>
          <p className="fl__muted">أول مرة؟ هيتعمل حسابك تلقائي بنفس البيانات دي.</p>

          <label htmlFor="fl-name">اسمك (أول مرة بس)</label>
          <input
            id="fl-name"
            className="fl__input"
            value={fullName}
            onChange={(e) => setFullName(e.target.value)}
          />

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

          <label htmlFor="fl-password">الباسورد</label>
          <input
            id="fl-password"
            className="fl__input"
            type="password"
            placeholder="٦ حروف/أرقام على الأقل"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            minLength={6}
            required
          />

          {error && <p className="fl__error">{error}</p>}
          <button type="submit" className="btn btn--brand" disabled={busy} style={{ inlineSize: '100%', marginBlockStart: 12 }}>
            {busy ? 'جاري الدخول...' : 'ادخل'}
          </button>
        </form>
      </div>
    </div>
  );
}
