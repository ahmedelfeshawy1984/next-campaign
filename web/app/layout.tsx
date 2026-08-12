import type { Metadata, Viewport } from 'next';
import { Cairo } from 'next/font/google';
import './globals.css';
import { S } from '@/lib/strings';
import { env, isConfigured } from '@/lib/env';
import SetupRequired from '@/components/SetupRequired';

// Cairo carries Arabic and Latin in one family, so a price in Western digits
// sitting inside an Arabic sentence does not switch typeface mid-line.
const cairo = Cairo({
  subsets: ['arabic', 'latin'],
  weight: ['400', '600', '700', '800', '900'],
  variable: '--font-cairo',
  display: 'swap',
});

export const metadata: Metadata = {
  metadataBase: new URL(env.siteUrl),
  title: { default: `${S.brand} — ${S.tagline}`, template: `%s — ${S.brand}` },
  description:
    'مطبوعات وهدايا دعائية للشركات في مصر: مجات وأقلام وأجندات وتيشرتات وفلاشات، مطبوعة بلوجو شركتك. وهدايا شخصية باسم صاحبها.',
  openGraph: {
    type: 'website',
    locale: 'ar_EG',
    siteName: S.brand,
  },
  robots: { index: true, follow: true },
};

export const viewport: Viewport = {
  themeColor: [
    { media: '(prefers-color-scheme: light)', color: '#ffffff' },
    { media: '(prefers-color-scheme: dark)', color: '#0f1117' },
  ],
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  // lang + dir on <html> is the whole RTL story. No Directionality wrapper, no
  // mirrored stylesheet — the layout uses logical properties throughout, so the
  // document direction is the only switch there is.
  return (
    <html lang="ar" dir="rtl" className={cairo.variable}>
      <body>
        {isConfigured ? (
          // Only what is genuinely global lives here. The shop's header and
          // footer moved to app/(shop)/layout.tsx — see the note in that file
          // for why hiding them was not the same as not running them.
          children
        ) : (
          // An empty catalogue looks like a bug in the data. A setup screen
          // looks like what it is. Same call as the sibling projects.
          <SetupRequired />
        )}
      </body>
    </html>
  );
}
