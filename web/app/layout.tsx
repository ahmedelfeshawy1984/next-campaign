import type { Metadata, Viewport } from 'next';
import './globals.css';
import { S } from '@/lib/strings';
import { env, isConfigured } from '@/lib/env';
import { getSiteSettings } from '@/lib/queries';
import SetupRequired from '@/components/SetupRequired';

// Cairo carries Arabic and Latin in one family, so a price in Western digits
// sitting inside an Arabic sentence does not switch typeface mid-line.
//
// It is declared in globals.css from files in web/public/fonts, NOT through
// next/font/google — see the comment at the top of that file. next/font
// downloads at build time, and a build that reaches out to a CDN is a build
// that fails when the CDN blinks. It did, and it took the deploy with it.

/**
 * The name in the browser tab, in Google's results and in a WhatsApp preview.
 *
 * Read from site_settings rather than hardcoded, for the same reason the header
 * is: changing the shop's own name must not require a developer. The constants
 * in lib/strings.ts are the fallback for a database nobody has filled in yet.
 */
export async function generateMetadata(): Promise<Metadata> {
  const settings = await getSiteSettings().catch(() => null);
  const brand = settings?.brand_name_ar || S.brand;
  const tagline = settings?.tagline_ar || S.tagline;

  return {
    metadataBase: new URL(env.siteUrl),
    title: { default: `${brand} — ${tagline}`, template: `%s — ${brand}` },
    description:
      'مطبوعات وهدايا دعائية للشركات في مصر: مجات وأقلام وأجندات وتيشرتات وفلاشات، مطبوعة بلوجو شركتك. وهدايا شخصية باسم صاحبها.',
    openGraph: {
      type: 'website',
      locale: 'ar_EG',
      siteName: brand,
    },
    robots: { index: true, follow: true },
  };
}

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
