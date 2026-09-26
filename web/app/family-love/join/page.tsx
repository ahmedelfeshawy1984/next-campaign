'use client';

import { Suspense, useState, type FormEvent } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { saveSession } from '@/lib/family-love/session';

function JoinForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [invite] = useState(searchParams.get('code') ?? '');
  const [phone, setPhone] = useState('');
  const [fullName, setFullName] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function join(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch('/api/family-love/members/join', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ code: invite, phone, password, fullName }),
      });
      if (!res.ok) {
        const data = (await res.json().catch(() => null)) as { error?: string } | null;
        if (data?.error === 'WRONG_PASSWORD') setError('الباسورد غلط.');
        else setError('كود الدعوة أو البيانات مش صحيحة.');
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

      <div className="fl__card fl__center">
        <div style={{ fontSize: 40, marginBlockEnd: 8 }}>👪</div>
        <h1 style={{ marginBlock: '0 4px', fontSize: '1.2rem' }}>انضم لعيلتك</h1>
        <p className="fl__muted">حد من عيلتك دعاك تنضم لمتابعة الأطفال معاه.</p>
      </div>

      <div className="fl__card">
        <form onSubmit={join}>
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

          <label htmlFor="fl-join-password">الباسورد (أول مرة بتحطه، أو باسوردك لو عندك حساب)</label>
          <input
            id="fl-join-password"
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
            {busy ? 'جاري الدخول...' : 'انضم للعيلة'}
          </button>
        </form>
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
