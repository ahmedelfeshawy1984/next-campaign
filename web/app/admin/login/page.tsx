'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { adminSignIn } from '@/lib/admin';
import { isEgMobile } from '@/lib/phone.js';

export default function AdminLoginPage() {
  const router = useRouter();
  const [phone, setPhone] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setBusy(true);
    try {
      await adminSignIn(phone, password);
      router.replace('/admin');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'مش قادرين ندخلك');
      setBusy(false);
    }
  }

  return (
    <section className="section">
      <form className="setup" onSubmit={submit} style={{ maxInlineSize: 420 }}>
        <h1 style={{ marginBlockEnd: 4 }}>دخول الإدارة</h1>
        <p className="cfg__hint" style={{ marginBlockEnd: 18 }}>
          بالموبايل المسجّل، مش بالإيميل.
        </p>

        <label className="field">
          <span>الموبايل</span>
          <input
            type="tel"
            dir="ltr"
            inputMode="numeric"
            autoComplete="username"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
          />
        </label>

        <label className="field">
          <span>كلمة السر</span>
          <input
            type="password"
            dir="ltr"
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
        </label>

        {error ? <p className="notice notice--warn">{error}</p> : null}

        <button
          type="submit"
          className="btn btn--brand"
          style={{ inlineSize: '100%' }}
          disabled={busy || !isEgMobile(phone) || password.length < 6}
        >
          {busy ? 'لحظة…' : 'دخول'}
        </button>
      </form>
    </section>
  );
}
