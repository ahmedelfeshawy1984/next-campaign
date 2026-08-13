'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import {
  currentStaff, clinicSignOut, canExamine, isDirector, ROLE_LABEL,
} from '@/lib/clinic/session';
import { syncCatalog, loadCatalog } from '@/lib/clinic/drugs';
import type { ClinicStaff } from '@/lib/clinic/types';
import OfflineBadge from './OfflineBadge';

// الشل — ودي مجاملة مش حاجز.
//
// Exactly the same standing as AdminShell: everything behind it returns
// nothing at all to someone without the role, because RLS decided so in the
// database. Deleting this component would leak no patient data — it would just
// leave somebody staring at empty screens.
//
// Worth keeping straight, because the day a blank screen gets "fixed" by
// loosening a policy instead of a redirect, the real gate is the one that
// moved.

interface NavItem {
  href: string;
  label: string;
  show: (s: ClinicStaff) => boolean;
}

const NAV: NavItem[] = [
  { href: '/clinic',          label: 'النهارده',  show: () => true },
  { href: '/clinic/queue',    label: 'الطابور',   show: () => true },
  { href: '/clinic/patients', label: 'المرضى',    show: () => true },
  { href: '/clinic/day',      label: 'حساب اليوم', show: (s) => s.role !== 'doctor' },
  { href: '/clinic/drugs',    label: 'الأدوية',   show: (s) => s.role !== 'reception' },
  { href: '/clinic/reports',  label: 'التقارير',  show: isDirector },
  { href: '/clinic/staff',    label: 'الفريق',    show: isDirector },
  { href: '/clinic/settings', label: 'الإعدادات', show: isDirector },
];

export default function ClinicShell({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const [staff, setStaff] = useState<ClinicStaff | null | undefined>(undefined);
  const [signOutError, setSignOutError] = useState<string | null>(null);

  const isLogin = pathname === '/clinic/login';

  useEffect(() => {
    currentStaff()
      .then((s) => {
        setStaff(s);
        if (!s && !isLogin) router.replace('/clinic/login');
        if (s && isLogin) router.replace('/clinic');

        // Pull whatever changed in the drug catalogue, then make sure the
        // in-memory copy is loaded either way. loadCatalog() is what the
        // picker searches, and it has to work when syncCatalog() just failed
        // for want of a network — that is the whole point of the local copy.
        if (s) void syncCatalog().catch(() => loadCatalog());
      })
      .catch(() => setStaff(null));
  }, [isLogin, router]);

  if (isLogin) return <>{children}</>;

  if (staff === undefined) return <p className="empty">لحظة…</p>;

  if (!staff) return <p className="empty">محتاج تدخل بحساب من العيادة.</p>;

  return (
    <div className="clinic">
      <header className="clinic__bar">
        <div className="wrap clinic__bar-inner">
          <Link href="/clinic" className="logo">
            <span className="logo__mark" aria-hidden="true" />
            العيادة
          </Link>

          <nav className="site-nav" aria-label="أقسام العيادة">
            {NAV.filter((n) => n.show(staff)).map((n) => (
              <Link
                key={n.href}
                href={n.href}
                aria-current={
                  n.href === '/clinic' ? pathname === '/clinic' : pathname.startsWith(n.href)
                }
              >
                {n.label}
              </Link>
            ))}
          </nav>

          <span className="spacer" />
          <OfflineBadge />

          <span className="cfg__hint clinic__who">
            {staff.display_name}
            <small>{ROLE_LABEL[staff.role]}</small>
          </span>

          <button
            type="button"
            className="btn btn--ghost btn--sm"
            onClick={async () => {
              setSignOutError(null);
              try {
                await clinicSignOut();
                router.replace('/clinic/login');
              } catch (e) {
                // Signing out wipes this device. Refusing while the outbox
                // still holds a prescription is the difference between tidying
                // up and destroying a medical record that exists nowhere else.
                const m = e instanceof Error ? e.message : '';
                setSignOutError(
                  m.startsWith('OUTBOX_NOT_EMPTY')
                    ? `فيه ${m.split(':')[1]} سجل لسه ما اترفعوش — استنى النت يرجع قبل الخروج.`
                    : 'مش قادرين نخرجك دلوقتي.'
                );
              }
            }}
          >
            خروج
          </button>
        </div>

        {signOutError ? (
          <p className="wrap clinic__bar-warn" role="alert">{signOutError}</p>
        ) : null}
      </header>

      {canExamine(staff) ? null : (
        <p className="wrap clinic__note">
          حسابك استقبال — بتشوف المرضى والمواعيد والفلوس، ومش بتشوف الكشوفات ولا الروشتات.
        </p>
      )}

      <div className="wrap clinic__body">{children}</div>
    </div>
  );
}
