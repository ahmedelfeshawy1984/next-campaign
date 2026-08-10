import Link from 'next/link';
import { S } from '@/lib/strings';

export default function NotFound() {
  return (
    <section className="section">
      <div className="wrap empty">
        <h1>{S.common.notFound}</h1>
        <p>{S.common.notFoundBody}</p>
        <div className="row" style={{ justifyContent: 'center', marginBlockStart: 16 }}>
          <Link href="/" className="btn btn--brand">
            {S.common.backHome}
          </Link>
          <Link href="/corporate" className="btn btn--ghost">
            {S.nav.corporate}
          </Link>
        </div>
      </div>
    </section>
  );
}
