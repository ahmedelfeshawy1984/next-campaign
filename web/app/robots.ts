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
        //
        // /clinic is patient data behind a login. Nothing there is reachable
        // without a session, but a crawler has no business asking, and a URL
        // that appears in a search result is a URL somebody tries.
        disallow: ['/admin', '/api', '/clinic'],
      },
    ],
    sitemap: absoluteUrl('/sitemap.xml'),
  };
}
