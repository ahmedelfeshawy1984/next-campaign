'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { clinicSignIn } from '@/lib/clinic/session';

export default function ClinicLogin() {
  const router = useRouter();
  const [phone, setPhone] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  return (
    <div className="wrap clinic__login">
      <h1>دخول العيادة</h1>
      <p className="cfg__hint">بالموبايل وكلمة السر اللي الديريكتور عملهالك.</p>

      <form
        onSubmit={async (e) => {
          e.preventDefault();
          setBusy(true);
          setError(null);
          try {
            await clinicSignIn(phone, password);
            router.replace('/clinic');
          } catch (err) {
            setError(err instanceof Error ? err.message : 'مش قادرين ندخلك');
            setBusy(false);
          }
        }}
      >
        <label>
          <span className="cfg__hint">الموبايل</span>
          <input
            className="input num"
            dir="ltr"
            inputMode="tel"
            autoComplete="username"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            required
          />
        </label>

        <label>
          <span className="cfg__hint">كلمة السر</span>
          <input
            className="input"
            type="password"
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          />
        </label>

        {error ? <p className="clinic__error" role="alert">{error}</p> : null}

        <button type="submit" className="btn btn--brand" disabled={busy}>
          {busy ? 'لحظة…' : 'دخول'}
        </button>
      </form>

      {/* The first thing that happens after signing in is a few hundred
          kilobytes of drug catalogue landing on this device. Saying so here
          means the one slow moment in the whole system is expected rather than
          alarming. */}
      <p className="cfg__hint clinic__login-note">
        أول مرة تدخل، كتالوج الأدوية بينزل على الجهاز — بعدها البحث بيشتغل من
        غير نت.
      </p>
    </div>
  );
}
