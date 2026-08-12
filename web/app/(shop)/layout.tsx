import SiteHeader from '@/components/SiteHeader';
import SiteFooter from '@/components/SiteFooter';

// هيدر وفوتر المحل — على صفحات المحل بس.
//
// A ROUTE GROUP, so the folder name changes no URL: app/(shop)/page.tsx is
// still `/` and app/(shop)/p/[slug] is still `/p/…`.
//
// WHY THIS RATHER THAN A CLIENT COMPONENT THAT HIDES THE CHROME
//
// Hiding is not the same as not running. SiteFooter is an async server
// component that reads site settings and the category list; passed as children
// to a client component that returns null, it STILL executes on the server,
// streams into the payload, and is then thrown away. That was measurable — the
// clinic's HTML carried a Suspense boundary and the footer's category links on
// every page load.
//
// Two database queries per page, for markup nobody sees, on the one screen in
// this codebase whose entire design goal is to keep working when the network
// does not. /admin was paying the same tax for nothing.
//
// The root layout above keeps <html>, <body>, the font and the setup guard —
// everything genuinely global. The shop's furniture lives here, and /clinic and
// /admin simply are not in this group.

export default function ShopLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      <SiteHeader />
      <main id="main">{children}</main>
      <SiteFooter />
    </>
  );
}
