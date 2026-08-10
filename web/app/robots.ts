import type { MetadataRoute } from 'next';
import { absoluteUrl } from '@/lib/env';

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      {
        userAgent: '*',
        allow: '/',
        // /admin arrives in P4 and must never be indexed. Listing it now costs
        // nothing and means the rule cannot be forgotten on the day it exists.
        disallow: ['/admin', '/api'],
      },
    ],
    sitemap: absoluteUrl('/sitemap.xml'),
  };
}
