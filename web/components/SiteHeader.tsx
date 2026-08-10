import Link from 'next/link';
import { S } from '@/lib/strings';
import BasketLink from './BasketLink';

const LINKS = [
  { href: '/corporate', label: S.nav.corporate },
  { href: '/gifts', label: S.nav.gifts },
  { href: '/printing', label: S.nav.printing },
  { href: '/about', label: S.nav.about },
];

export default function SiteHeader() {
  return (
    <header className="site-header">
      <div className="wrap site-header__inner">
        <Link href="/" className="logo">
          <span className="logo__mark" aria-hidden="true" />
          {S.brand}
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
