'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { currentAdmin, adminSignOut, type AdminSession } from '@/lib/admin';

const NAV = [
  { href: '/admin', label: 'اليوم' },
  { href: '/admin/requests', label: 'الطلبات' },
  { href: '/admin/products', label: 'المنتجات' },
  { href: '/admin/lists', label: 'الفئات والمناسبات' },
  { href: '/admin/settings', label: 'الإعدادات' },
  { href: '/admin/staff', label: 'المستخدمين' },
];

/**
 * The guard, and it is a COURTESY not a boundary.
 *
 * Everything behind it returns nothing at all to a non-manager because of RLS —
 * deleting this component would leak no data, it would just leave somebody
 * staring at empty tables. That distinction is worth keeping straight: the day
 * somebody "fixes" a blank screen by loosening a policy instead of a redirect,
 * the real gate is the one that moved.
 */
export default function AdminShell({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const [session, setSession] = useState<AdminSession | null | undefined>(undefined);

  const isLogin = pathname === '/admin/login';

  useEffect(() => {
    currentAdmin()
      .then((s) => {
        setSession(s);
        if (!s?.isManager && !isLogin) router.replace('/admin/login');
        if (s?.isManager && isLogin) router.replace('/admin');
      })
      .catch(() => setSession(null));
  }, [isLogin, router]);

  if (isLogin) return <>{children}</>;

  if (session === undefined) {
    return <p className="empty">لحظة…</p>;
  }

  if (!session?.isManager) {
    return <p className="empty">محتاج تدخل بحساب إدارة.</p>;
  }

  return (
    <div className="admin">
      <header className="admin__bar">
        <div className="wrap admin__bar-inner">
          <Link href="/admin" className="logo">
            <span className="logo__mark" aria-hidden="true" />
            الإدارة
          </Link>
          <nav className="site-nav" aria-label="أقسام الإدارة">
            {NAV.map((n) => (
              <Link
                key={n.href}
                href={n.href}
                aria-current={
                  n.href === '/admin' ? pathname === '/admin' : pathname.startsWith(n.href)
                }
              >
                {n.label}
              </Link>
            ))}
          </nav>
          <span className="spacer" />
          <span className="cfg__hint">{session.fullName}</span>
          <button
            type="button"
            className="btn btn--ghost btn--sm"
            onClick={async () => {
              await adminSignOut();
              router.replace('/admin/login');
            }}
          >
            خروج
          </button>
        </div>
      </header>
      <div className="wrap admin__body">{children}</div>
    </div>
  );
}
