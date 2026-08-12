import Link from 'next/link';
import Image from 'next/image';
import { S } from '@/lib/strings';
import { getSiteSettings } from '@/lib/queries';
import { mediaUrl } from '@/lib/supabase';
import BasketLink from './BasketLink';

const LINKS = [
  { href: '/corporate', label: S.nav.corporate },
  { href: '/gifts', label: S.nav.gifts },
  { href: '/printing', label: S.nav.printing },
  { href: '/about', label: S.nav.about },
];

export default async function SiteHeader() {
  // The name and the mark come from site_settings, not from a constant in the
  // source. A shop's own name is the first thing it wants to change and the
  // last thing it should need a developer for — S.brand is only the fallback
  // for a database that has not been filled in yet.
  const settings = await getSiteSettings().catch(() => null);
  const brand = settings?.brand_name_ar || S.brand;
  const logo = mediaUrl(settings?.logo_url);

  return (
    <header className="site-header">
      <div className="wrap site-header__inner">
        <Link href="/" className="logo">
          {logo ? (
            <Image
              src={logo}
              alt={brand}
              width={140}
              height={40}
              priority
              className="logo__img"
            />
          ) : (
            <>
              {/* No logo uploaded yet: a coloured mark in the brand colour,
                  which reads as a deliberate placeholder rather than a broken
                  image. */}
              <span className="logo__mark" aria-hidden="true" />
              {brand}
            </>
          )}
        </Link>
        <nav className="site-nav" aria-label="التنقل الرئيسي">
          {LINKS.map((l) => (
            <Link key={l.href} href={l.href}>
              {l.label}
            </Link>
          ))}
        </nav>
        <span className="spacer" />
        <BasketLink />
      </div>
    </header>
  );
}
