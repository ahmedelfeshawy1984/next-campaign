/* السيرفس ووركر — للعيادة بس.
 *
 * ⚠ SCOPE IS /clinic/ AND NOTHING ABOVE IT. Registered with an explicit scope
 *   in components/clinic/ServiceWorker.tsx.
 *
 *   A worker at the root would also sit in front of the shop, and the shop is a
 *   server-rendered catalogue whose whole reason for existing (docs/القرارات.md)
 *   is that Google and WhatsApp can read it and a price change is live at once.
 *   Cache-first in front of that serves yesterday's price to a customer and a
 *   stale page to a crawler.
 *
 * WHAT THIS DOES AND DOES NOT DO
 *
 *   It caches the SHELL — the HTML, JS and CSS needed to open the app with no
 *   network. It does NOT cache data, and it must not: patient data lives in
 *   IndexedDB, which the app manages deliberately, and a second copy in the
 *   Cache API would be a second copy nobody clears on sign-out.
 *
 *   So: navigations and static assets are network-first with a cache fallback;
 *   everything else — every PostgREST call — is left entirely alone.
 */

const CACHE = 'clinic-shell-v1';

// Only what is needed to boot. Next fingerprints its own assets, so they are
// picked up as they are fetched rather than listed here where they would go
// stale on the next deploy.
const SEED = ['/clinic', '/clinic/patients', '/clinic/queue'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE)
      // Individually, and swallowing failures: one 404 in addAll() rejects the
      // whole install and leaves the clinic with no offline shell at all.
      .then((cache) => Promise.all(SEED.map((url) => cache.add(url).catch(() => {}))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);

  // Anything that is not this origin is the database or a font CDN. Not ours
  // to cache — supabase-js and the app's own outbox handle those failures with
  // far more context than a worker has.
  if (url.origin !== self.location.origin) return;

  const isShell =
    request.mode === 'navigate' ||
    url.pathname.startsWith('/_next/static/') ||
    url.pathname.startsWith('/clinic-icon') ||
    url.pathname === '/clinic.webmanifest';

  if (!isShell) return;

  // NETWORK FIRST, not cache first. A doctor opening the app on a working
  // connection should get today's build; the cache is the fallback for the
  // moment there is no connection, not the default source of truth.
  event.respondWith(
    fetch(request)
      .then((response) => {
        if (response.ok) {
          const copy = response.clone();
          caches.open(CACHE).then((cache) => cache.put(request, copy));
        }
        return response;
      })
      .catch(async () => {
        const hit = await caches.match(request);
        if (hit) return hit;
        // A route never visited while online. Falling back to the home screen
        // beats the browser's dinosaur: the app boots, the local database is
        // there, and the doctor can still write.
        if (request.mode === 'navigate') {
          const home = await caches.match('/clinic');
          if (home) return home;
        }
        return Response.error();
      })
  );
});
