// Hits every route against a running server and checks what the crawler and
// the WhatsApp scraper will see.
//
// WhatsApp preview is an explicit requirement of this project and it breaks
// SILENTLY — a missing og:title costs nothing at build time and everything when
// the owner sends a product link to a client and a bare grey box comes back.
//
// Start the server first, then:
//   G:\dev-tools\node\node.exe tools/web-check/routes.mjs [baseUrl]

const base = (process.argv[2] ?? 'http://localhost:3000').replace(/\/$/, '');

const results = [];
const check = (name, ok, detail = '') => {
  results.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  -> ' + detail : ''}`);
};

/** @param {string} html @param {string} property */
function meta(html, property) {
  const re = new RegExp(
    `<meta[^>]+(?:property|name)=["']${property}["'][^>]+content=["']([^"']*)["']`,
    'i'
  );
  const alt = new RegExp(
    `<meta[^>]+content=["']([^"']*)["'][^>]+(?:property|name)=["']${property}["']`,
    'i'
  );
  return html.match(re)?.[1] ?? html.match(alt)?.[1] ?? null;
}

async function get(path) {
  const res = await fetch(`${base}${path}`, { redirect: 'manual' });
  const body = res.status >= 200 && res.status < 300 ? await res.text() : '';
  return { status: res.status, location: res.headers.get('location'), body };
}

const STATIC_ROUTES = ['/', '/corporate', '/gifts', '/printing', '/about', '/sitemap.xml', '/robots.txt'];

try {
  for (const path of STATIC_ROUTES) {
    const { status } = await get(path);
    check(`GET ${path}`, status === 200, `HTTP ${status}`);
  }

  // The sitemap is the list of everything that must resolve. Reading the routes
  // from it rather than hardcoding them means a product added tomorrow is
  // checked tomorrow, without editing this file.
  const sitemap = (await get('/sitemap.xml')).body;
  const urls = [...sitemap.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
  check('sitemap lists routes', urls.length >= 10, `${urls.length} URLs`);

  const paths = urls.map((u) => new URL(u).pathname);
  const products = paths.filter((p) => p.startsWith('/p/'));
  const categories = paths.filter((p) => p.startsWith('/c/'));
  const occasions = paths.filter((p) => p.startsWith('/o/'));
  check('sitemap includes product pages', products.length > 0, `${products.length}`);
  check('sitemap includes category pages', categories.length > 0, `${categories.length}`);
  check('sitemap includes occasion pages', occasions.length > 0, `${occasions.length}`);

  let bad = [];
  for (const p of paths) {
    const { status } = await get(p);
    if (status !== 200) bad.push(`${p} → ${status}`);
  }
  check('every URL in the sitemap resolves', bad.length === 0, bad.join(', ') || `${paths.length} OK`);

  // A crawler and a scraper both read the head. Three product pages is enough
  // to catch a template-level regression, which is the only kind there is.
  let noTitle = [];
  let noDesc = [];
  let noImage = [];
  let brokenImage = [];
  for (const p of products.slice(0, 3)) {
    const { body } = await get(p);
    const title = meta(body, 'og:title');
    const desc = meta(body, 'og:description');
    const image = meta(body, 'og:image');

    if (!title) noTitle.push(p);
    if (!desc) noDesc.push(p);
    if (!image) noImage.push(p);
    else {
      const res = await fetch(image, { method: 'HEAD' }).catch(() => null);
      const type = res?.headers.get('content-type') ?? '';
      if (!res?.ok || !type.startsWith('image/')) brokenImage.push(`${p} → ${image}`);
    }
  }
  check('every product page has og:title', noTitle.length === 0, noTitle.join(', '));
  check('every product page has og:description', noDesc.length === 0, noDesc.join(', '));
  check(
    'no product page points og:image at something that is not an image',
    brokenImage.length === 0,
    brokenImage.join(', ')
  );
  // Not a failure while the catalogue has no photographs, but it is the single
  // thing that makes a shared link look like a real shop, so it is counted out
  // loud on every run.
  check(
    'products with no og:image are counted (a link with no picture is a grey box)',
    true,
    `${noImage.length} of ${Math.min(products.length, 3)} sampled have no cover photo`
  );

  // Structured data — the other half of what Google reads.
  const sample = products[0];
  if (sample) {
    const { body } = await get(sample);
    const ld = body.match(/<script type="application\/ld\+json">([^<]+)<\/script>/)?.[1];
    let parsed = null;
    try {
      parsed = ld ? JSON.parse(ld) : null;
    } catch {
      parsed = null;
    }
    check(
      'the product page carries valid Product JSON-LD',
      parsed?.['@type'] === 'Product' && !!parsed?.name,
      parsed ? `${parsed['@type']} · ${parsed.name}` : 'missing or unparseable'
    );
  }

  // RTL, checked where it actually lives.
  const home = (await get('/')).body;
  check(
    'the document declares Arabic and RTL',
    /<html[^>]+lang="ar"/.test(home) && /<html[^>]+dir="rtl"/.test(home),
    home.match(/<html[^>]*>/)?.[0]?.slice(0, 90)
  );
  check(
    'the home page is server-rendered, not an empty shell',
    home.includes('<h1'),
    `${Math.round(home.length / 1024)} kB of HTML`
  );

  const notFound = await get('/p/this-slug-does-not-exist');
  check('an unknown product slug 404s', notFound.status === 404, `HTTP ${notFound.status}`);

  // ---- العيادة ---------------------------------------------------------------
  //
  // The clinic is patient data behind a login, and the checks here are about
  // it staying OUT of everything the shop publishes. The access control itself
  // is RLS and is asserted in tools/schema-check/clinic.mjs; what a crawler
  // can find is this file's business.

  const clinicInSitemap = paths.filter((p) => p.startsWith('/clinic'));
  check(
    'no clinic route appears in the sitemap',
    clinicInSitemap.length === 0,
    clinicInSitemap.join(', ') || 'none'
  );

  const robots = (await get('/robots.txt')).body;
  check(
    'robots.txt disallows /clinic',
    /Disallow:\s*\/clinic/i.test(robots),
    robots.split('\n').filter((l) => /disallow/i.test(l)).join(' | ')
  );

  const clinicHome = await get('/clinic');
  check(
    'GET /clinic serves the app shell',
    clinicHome.status === 200,
    `HTTP ${clinicHome.status}`
  );
  // The gate is a session check that runs in the browser and a database that
  // returns nothing without one. What must NOT happen is patient data arriving
  // in the server-rendered HTML, where a crawler or a shared link would carry
  // it without anyone signing in.
  check(
    'the clinic shell is served with noindex',
    /noindex/i.test(clinicHome.body),
    'robots meta present'
  );

  const manifest = await get('/clinic.webmanifest');
  let parsedManifest = null;
  try {
    parsedManifest = JSON.parse(manifest.body);
  } catch { /* reported below */ }
  check(
    'the PWA manifest is served and parses',
    manifest.status === 200 && !!parsedManifest,
    `HTTP ${manifest.status}`
  );
  // Scope is what keeps the service worker off the shop. Worth asserting,
  // because widening it is a one-character edit with consequences nobody would
  // connect back to it.
  check(
    'the manifest is scoped to /clinic/ only',
    parsedManifest?.scope === '/clinic/',
    parsedManifest?.scope ?? 'missing'
  );

  const sw = await get('/clinic-sw.js');
  check(
    'the service worker is served from the origin root so it can claim /clinic/',
    sw.status === 200,
    `HTTP ${sw.status}`
  );

  // The shop must not have become installable or worker-controlled by
  // accident — the whole point of scoping both.
  check(
    'the shop home page links no manifest',
    !/rel="manifest"/i.test(home),
    'clean'
  );
} finally {
  const failed = results.filter((r) => !r.ok);
  console.log(`\n${results.length - failed.length}/${results.length} passed`);
  if (failed.length) {
    console.log('\nFAILED:');
    for (const f of failed) console.log(`  - ${f.name}${f.detail ? ' -> ' + f.detail : ''}`);
  }
  process.exit(failed.length ? 1 : 0);
}
