import type { Metadata, Viewport } from 'next';
import ClinicShell from '@/components/clinic/ClinicShell';
import ServiceWorker from '@/components/clinic/ServiceWorker';
import './clinic.css';

export const metadata: Metadata = {
  title: 'العيادة',
  // Overridden, not inherited. Without these two the clinic's pages carry the
  // shop's description and og: tags — so a link pasted into WhatsApp previews
  // a prescription screen as "مطبوعات وهدايا دعائية".
  description: 'روشتات وملفات مرضى.',
  openGraph: { title: 'العيادة', description: 'روشتات وملفات مرضى.' },
  // Never indexed. robots.ts disallows /clinic as well — belt and braces,
  // because one of the two is always the one somebody edits by accident.
  robots: { index: false, follow: false, nocache: true },
  // The manifest is linked HERE and not in the root layout, so the shop does
  // not quietly become installable as "العيادة" on a customer's phone.
  manifest: '/clinic.webmanifest',
  appleWebApp: { capable: true, title: 'العيادة', statusBarStyle: 'default' },
};

export const viewport: Viewport = {
  // The clinic is used one-handed on a phone between patients. Locking the
  // scale would fight a doctor trying to read a dose; letting the browser
  // decide the initial one is enough.
  initialScale: 1,
  width: 'device-width',
  themeColor: '#0f766e',
};

export default function ClinicLayout({ children }: { children: React.ReactNode }) {
  // Its own <main>, for the same reason as app/admin/layout.tsx: the landmark
  // used to come from the root layout and moved out with the shop's chrome.
  return (
    <main id="main">
      <ServiceWorker />
      <ClinicShell>{children}</ClinicShell>
    </main>
  );
}
