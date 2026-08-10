import type { MetadataRoute } from 'next';
import { getAllRoutes } from '@/lib/queries';
import { absoluteUrl } from '@/lib/env';
import { isConfigured } from '@/lib/env';

export const revalidate = 3600;

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const statics: MetadataRoute.Sitemap = [
    { url: absoluteUrl('/'), changeFrequency: 'weekly', priority: 1 },
    { url: absoluteUrl('/corporate'), changeFrequency: 'weekly', priority: 0.9 },
    { url: absoluteUrl('/gifts'), changeFrequency: 'weekly', priority: 0.9 },
    { url: absoluteUrl('/printing'), changeFrequency: 'monthly', priority: 0.7 },
    { url: absoluteUrl('/about'), changeFrequency: 'yearly', priority: 0.4 },
  ];

  // A build with no database still has to produce a valid sitemap rather than
  // a 500 — the static pages are true regardless.
  if (!isConfigured) return statics;

  const { products, categories, occasions } = await getAllRoutes().catch(() => ({
    products: [],
    categories: [],
    occasions: [],
  }));

  return [
    ...statics,
    ...categories.map((c) => ({
      url: absoluteUrl(`/c/${c.slug}`),
      changeFrequency: 'weekly' as const,
      priority: 0.8,
    })),
    ...occasions.map((o) => ({
      url: absoluteUrl(`/o/${o.slug}`),
      changeFrequency: 'monthly' as const,
      priority: 0.6,
    })),
    ...products.map((p) => ({
      url: absoluteUrl(`/p/${p.slug}`),
      lastModified: p.updated_at ? new Date(p.updated_at) : undefined,
      changeFrequency: 'weekly' as const,
      priority: 0.9,
    })),
  ];
}
