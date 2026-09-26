'use client';

import { Suspense, useState, type FormEvent } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { saveSession } from '@/lib/family-love/session';

function PairForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [code, setCode] = useState(searchParams.get('code') ?? '');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function redeem(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch('/api/family-love/pairing/redeem', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ code }),
      });
      if (!res.ok) throw new Error();
      const data = (await res.json()) as { accessToken: string; refreshToken: string; expiresIn: number };
      saveSession({
        refreshToken: data.refreshToken,
        kind: 'child',
        accessToken: data.accessToken,
        expiresIn: data.expiresIn,
      });
      router.replace('/family-love/child');
    } catch {
      setError('الكود ده مش شغال، اطلب من ماما أو بابا كود جديد.');
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
        <div style={{ fontSize: 40, marginBlockEnd: 8 }}>👋</div>
        <h1 style={{ marginBlock: '0 4px', fontSize: '1.2rem' }}>أهلاً بيك!</h1>
        <p className="fl__muted">اكتب الكود اللي بعتهولك ماما أو بابا.</p>
      </div>

      <form onSubmit={redeem} className="fl__card">
        <label htmlFor="fl-pair-code">الكود</label>
        <input
          id="fl-pair-code"
          className="fl__input"
          style={{ textAlign: 'center', fontSize: '1.4rem', letterSpacing: '0.2em' }}
          type="text"
          autoCapitalize="characters"
          value={code}
          onChange={(e) => setCode(e.target.value.toUpperCase())}
          required
        />
        {error && <p className="fl__error">{error}</p>}
        <button type="submit" className="btn btn--brand" disabled={busy} style={{ inlineSize: '100%', marginBlockStart: 12 }}>
          {busy ? 'جاري الدخول...' : 'يلا بينا'}
        </button>
      </form>
    </div>
  );
}

export default function FamilyLovePairPage() {
  return (
    <Suspense fallback={null}>
      <PairForm />
    </Suspense>
  );
}
