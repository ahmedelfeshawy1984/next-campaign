/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,

  // Preview mode (rendering the catalogue from the seed with no Supabase
  // project) is NOT configured here. A resolve.alias for '@/lib/queries' loses
  // to the tsconfig-paths plugin in both Turbopack and webpack, so it silently
  // did nothing. See tools/preview/toggle.mjs for what replaced it and why.

  // Product photos live in Supabase Storage. The hostname comes from the same
  // env var the data client uses, so a project change cannot leave the image
  // allow-list pointing at the old one.
  images: (() => {
    const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
    if (!url) return { remotePatterns: [] };
    try {
      return {
        remotePatterns: [
          { protocol: 'https', hostname: new URL(url).hostname, pathname: '/storage/v1/object/**' },
        ],
      };
    } catch {
      return { remotePatterns: [] };
    }
  })(),
};

export default nextConfig;
