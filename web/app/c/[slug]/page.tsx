import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { getCategoryBySlug, getCategories } from '@/lib/queries';
import CatalogView from '@/components/CatalogView';
import type { SearchParams } from '@/lib/urls';

export const revalidate = 300;

export async function generateStaticParams() {
  const categories = await getCategories().catch(() => []);
  return categories.map((c) => ({ slug: c.slug }));
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const category = await getCategoryBySlug(slug).catch(() => null);
  if (!category) return {};
  const title = category.seo_title_ar ?? category.name_ar;
  return {
    title,
    description: category.seo_desc_ar ?? category.blurb_ar ?? undefined,
    alternates: { canonical: `/c/${category.slug}` },
    openGraph: {
      title,
      description: category.seo_desc_ar ?? category.blurb_ar ?? undefined,
      url: `/c/${category.slug}`,
    },
  };
}

export default async function CategoryPage({
  params,
  searchParams,
}: {
  params: Promise<{ slug: string }>;
  searchParams: Promise<SearchParams>;
}) {
  const [{ slug }, sp] = await Promise.all([params, searchParams]);
  const category = await getCategoryBySlug(slug);
  if (!category || !category.is_active) notFound();

  return (
    <>
      <section className="section section--tight section--surface">
        <div className="wrap">
          <h1>{category.name_ar}</h1>
          {category.blurb_ar ? <p className="lead">{category.blurb_ar}</p> : null}
        </div>
      </section>
      <CatalogView
        basePath={`/c/${category.slug}`}
        searchParams={sp}
        fixed={{ category: category.slug }}
        locked={['category']}
      />
    </>
  );
}
