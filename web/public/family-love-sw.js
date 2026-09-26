/* السيرفس ووركر — لـ /family-love/ بس.
 *
 * ⚠ النطاق /family-love/ بس، مسجّل بنطاق صريح في
 *   components/family-love/ServiceWorker.tsx — بالظبط نفس سبب العيادة: مينفعش
 *   يتخطى لباقي المستودع.
 *
 * بيعمل حاجتين بس:
 *   ١. كاش الهيكل (shell) — الصفحة والـ JS/CSS الأساسيين، عشان يفتح من غير نت.
 *      Network-first مع fallback للكاش، مش العكس.
 *   ٢. استقبال Web Push وعرضه كإشعار — العيادة معندهاش الجزء ده خالص.
 *
 * البيانات نفسها (المهام، المواقع، الرسايل) بتعدي كلها عن طريق Supabase مباشرة
 * ومالهاش دعوة بالكاش هنا.
 */

const CACHE = 'family-love-shell-v1';

const SEED = ['/family-love', '/family-love/home', '/family-love/child'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE)
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
  if (url.origin !== self.location.origin) return;

  const isShell =
    request.mode === 'navigate' ||
    url.pathname.startsWith('/_next/static/') ||
    url.pathname.startsWith('/family-love-icon') ||
    url.pathname === '/family-love.webmanifest';

  if (!isShell) return;

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
        if (request.mode === 'navigate') {
          const home = await caches.match('/family-love');
          if (home) return home;
        }
        return Response.error();
      })
  );
});

/* -------------------------------------------------------------- Push --- */

self.addEventListener('push', (event) => {
  let payload = { title: 'عائلتي', body: '' , url: '/family-love/home' };
  try {
    if (event.data) payload = { ...payload, ...event.data.json() };
  } catch {
    // إشعار بلا بيانات JSON صالحة — نعرض العنوان الافتراضي بدل ما نكسر.
  }

  event.waitUntil(
    self.registration.showNotification(payload.title, {
      body: payload.body,
      icon: '/family-love-icon.svg',
      badge: '/family-love-icon.svg',
      data: { url: payload.url },
    })
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = event.notification.data?.url || '/family-love/home';

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clients) => {
      for (const client of clients) {
        if (client.url.includes(target) && 'focus' in client) return client.focus();
      }
      return self.clients.openWindow(target);
    })
  );
});
