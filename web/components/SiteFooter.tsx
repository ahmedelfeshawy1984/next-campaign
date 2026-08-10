import Link from 'next/link';
import { S } from '@/lib/strings';
import { getSiteSettings, getCategories } from '@/lib/queries';
import { prettyPhone } from '@/lib/phone';
import { whatsappLink } from '@/lib/whatsapp';

export default async function SiteFooter() {
  // A failure to read settings must not take the whole page down — the footer
  // is the least important thing on it.
  const [settings, categories] = await Promise.all([
    getSiteSettings().catch(() => null),
    getCategories().catch(() => []),
  ]);

  const wa = whatsappLink(settings?.whatsapp_phone, 'السلام عليكم، عايز أستفسر عن الهدايا الدعائية');

  return (
    <footer className="site-footer">
      <div className="wrap">
        <div className="footer-grid">
          <div>
            <h4>{settings?.brand_name_ar ?? S.brand}</h4>
            <p>{settings?.tagline_ar ?? S.tagline}</p>
            {settings?.working_hours_ar ? <p>{settings.working_hours_ar}</p> : null}
          </div>

          <div>
            <h4>الفئات</h4>
            <div className="stack">
              {categories.slice(0, 6).map((c) => (
                <div key={c.id}>
                  <Link href={`/c/${c.slug}`}>{c.name_ar}</Link>
                </div>
              ))}
            </div>
          </div>

          <div>
            <h4>روابط</h4>
            <div className="stack">
              <div><Link href="/corporate">{S.nav.corporate}</Link></div>
              <div><Link href="/gifts">{S.nav.gifts}</Link></div>
              <div><Link href="/printing">{S.nav.printing}</Link></div>
              <div><Link href="/about">{S.nav.about}</Link></div>
            </div>
          </div>

          <div>
            <h4>{S.nav.contact}</h4>
            <div className="stack">
              {settings?.hotline ? (
                <div>
                  <a href={`tel:${settings.hotline}`} className="num" dir="ltr">
                    {prettyPhone(settings.hotline)}
                  </a>
                </div>
              ) : null}
              {settings?.email ? (
                <div>
                  <a href={`mailto:${settings.email}`} dir="ltr">{settings.email}</a>
                </div>
              ) : null}
              {settings?.address_ar ? <div>{settings.address_ar}</div> : null}
              {wa ? (
                <div style={{ marginBlockStart: 8 }}>
                  <a
                    className="btn btn--brand btn--sm"
                    href={wa}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    {S.common.whatsapp}
                  </a>
                </div>
              ) : null}
            </div>
          </div>
        </div>

        <div className="footer-bottom">
          <span className="num">© {new Date().getFullYear()}</span> {settings?.brand_name_ar ?? S.brand}
          {' · '}
          {settings?.prices_include_vat ? S.common.vatNoteIncluded : S.common.vatNote}
        </div>
      </div>
    </footer>
  );
}
