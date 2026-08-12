import type { Metadata, Viewport } from 'next';
import './globals.css';
import { S } from '@/lib/strings';
import { env, isConfigured } from '@/lib/env';
import SiteHeader from '@/components/SiteHeader';
import SiteFooter from '@/components/SiteFooter';
import SetupRequired from '@/components/SetupRequired';

// Cairo carries Arabic and Latin in one family, so a price in Western digits
// sitting inside an Arabic sentence does not switch typeface mid-line.
//
// It is declared in globals.css from files in web/public/fonts, NOT through
// next/font/google — see the comment at the top of that file. next/font
// downloads at build time, and a build that reaches out to a CDN is a build
// that fails when the CDN blinks. It did, and it took the deploy with it.

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
    <html lang="ar" dir="rtl">
      <body>
        {isConfigured ? (
          <>
            <SiteHeader />
            <main id="main">{children}</main>
            <SiteFooter />
          </>
        ) : (
          // An empty catalogue looks like a bug in the data. A setup screen
          // looks like what it is. Same call as the sibling projects.
          <SetupRequired />
        )}
      </body>
    </html>
  );
}
