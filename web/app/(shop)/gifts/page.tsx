import type { Metadata } from 'next';
import Link from 'next/link';
import { S } from '@/lib/strings';
import CatalogView from '@/components/CatalogView';
import { getOccasions } from '@/lib/queries';
import type { SearchParams } from '@/lib/urls';

export const revalidate = 300;

export const metadata: Metadata = {
  title: S.gifts.title,
  description: S.gifts.body,
  alternates: { canonical: '/gifts' },
};

export default async function GiftsPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const [sp, occasions] = await Promise.all([searchParams, getOccasions()]);

  return (
    <>
      <section className="section section--tight section--surface">
        <div className="wrap">
          <h1>{S.gifts.title}</h1>
          <p className="lead">{S.gifts.body}</p>
          {/* Occasion first for individuals: nobody shops for "a mug", they
              shop for a birthday. Corporates come in by product category. */}
          <div className="chip-row" style={{ marginBlockStart: 14 }}>
            {occasions.map((o) => (
              <Link key={o.id} href={`/o/${o.slug}`} className="chip">
                {o.name_ar}
              </Link>
            ))}
          </div>
        </div>
      </section>
      <CatalogView
        basePath="/gifts"
        searchParams={sp}
        fixed={{ audience: 'individual' }}
        locked={['audience']}
      />
    </>
  );
}
