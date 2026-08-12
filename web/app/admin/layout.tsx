import type { Metadata } from 'next';
import AdminShell from '@/components/admin/AdminShell';

export const metadata: Metadata = {
  title: 'الإدارة',
  // Never indexed. robots.ts disallows /admin as well — belt and braces,
  // because one of the two is always the one somebody edits by accident.
  robots: { index: false, follow: false, nocache: true },
};

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  // The <main> landmark used to come from the root layout. It moved out with
  // the shop's chrome into app/(shop)/layout.tsx, so each area that is not the
  // shop provides its own — a page with no main landmark is a page a screen
  // reader cannot skip into.
  return (
    <main id="main">
      <AdminShell>{children}</AdminShell>
    </main>
  );
}
