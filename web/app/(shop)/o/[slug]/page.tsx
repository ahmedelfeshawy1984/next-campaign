import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { getOccasionBySlug, getOccasions } from '@/lib/queries';
import CatalogView from '@/components/CatalogView';
import type { SearchParams } from '@/lib/urls';

export const revalidate = 300;

export async function generateStaticParams() {
  const occasions = await getOccasions().catch(() => []);
  return occasions.map((o) => ({ slug: o.slug }));
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const occasion = await getOccasionBySlug(slug).catch(() => null);
  if (!occasion) return {};
  const title = occasion.seo_title_ar ?? `هدايا ${occasion.name_ar}`;
  return {
    title,
    description: occasion.seo_desc_ar ?? occasion.blurb_ar ?? undefined,
    alternates: { canonical: `/o/${occasion.slug}` },
    openGraph: {
      title,
      description: occasion.seo_desc_ar ?? occasion.blurb_ar ?? undefined,
      url: `/o/${occasion.slug}`,
    },
  };
}

export default async function OccasionPage({
  params,
  searchParams,
}: {
  params: Promise<{ slug: string }>;
  searchParams: Promise<SearchParams>;
}) {
  const [{ slug }, sp] = await Promise.all([params, searchParams]);
  const occasion = await getOccasionBySlug(slug);
  if (!occasion || !occasion.is_active) notFound();

  return (
    <>
      <section className="section section--tight section--surface">
        <div className="wrap">
          <h1>هدايا {occasion.name_ar}</h1>
          {occasion.blurb_ar ? <p className="lead">{occasion.blurb_ar}</p> : null}
        </div>
      </section>
      <CatalogView
        basePath={`/o/${occasion.slug}`}
        searchParams={sp}
        fixed={{ occasion: occasion.slug }}
        locked={['occasion']}
      />
    </>
  );
}
