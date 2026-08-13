import type { Metadata } from 'next';
import { S } from '@/lib/strings';
import CatalogView from '@/components/CatalogView';
import type { SearchParams } from '@/lib/urls';

export const revalidate = 300;

export const metadata: Metadata = {
  title: S.corporate.title,
  description: S.corporate.body,
  alternates: { canonical: '/corporate' },
};

export default async function CorporatePage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const sp = await searchParams;
  return (
    <>
      <section className="section section--tight section--surface">
        <div className="wrap">
          <h1>{S.corporate.title}</h1>
          <p className="lead">{S.corporate.body}</p>
        </div>
      </section>
      <CatalogView
        basePath="/corporate"
        searchParams={sp}
        fixed={{ audience: 'corporate' }}
        locked={['audience']}
      />
    </>
  );
}
