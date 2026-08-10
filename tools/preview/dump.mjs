// Renders the catalogue WITHOUT a Supabase project.
//
// Boots the same throwaway Postgres the schema harness uses, applies the real
// migrations and the real seed, then writes every shape the site reads into one
// JSON file. `npm run preview` in web/ serves the site from that file.
//
// This exists because the owner should be able to look at the catalogue before
// creating a Supabase project — reviewing a design and setting up a database
// are two different afternoons. The data is the real seed, not a mock, so what
// he sees is what the site renders.
//
//   G:\dev-tools\node\node.exe tools/preview/dump.mjs

import { fileURLToPath } from 'node:url';
import { dirname, resolve, join } from 'node:path';
import { readFileSync, readdirSync, writeFileSync, mkdirSync } from 'node:fs';
import EmbeddedPostgresMod from 'embedded-postgres';
import { AUTH_STUB, clearDataDir } from '../schema-check/stub.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const EmbeddedPostgres = EmbeddedPostgresMod.default ?? EmbeddedPostgresMod;
const MIG = resolve(here, '../../supabase/migrations');
const SEED = resolve(here, '../../supabase/seed.sql');
const OUT = resolve(here, '../../web/preview-data.json');

const dataDir = join(here, 'pgdata');
clearDataDir(dataDir);

const pg = new EmbeddedPostgres({
  databaseDir: dataDir,
  user: 'postgres',
  password: 'postgres',
  port: 54996,
  persistent: false,
  initdbFlags: ['--encoding=UTF8', '--locale=C'],
});

console.log('booting postgres...');
await pg.initialise();
await pg.start();

const client = pg.getPgClient();
await client.connect();

const rows = async (sql, params = []) => (await client.query(sql, params)).rows;

try {
  await client.query(AUTH_STUB);
  for (const f of readdirSync(MIG).filter((f) => f.endsWith('.sql')).sort()) {
    await client.query(readFileSync(join(MIG, f), 'utf8'));
  }
  await client.query(readFileSync(SEED, 'utf8'));
  console.log('migrations + seed applied.');

  const settings = (await rows('select * from site_settings'))[0] ?? null;
  const categories = await rows('select * from categories where is_active order by sort_order');
  const occasions = await rows('select * from occasions where is_active order by sort_order');
  const methods = await rows('select * from print_methods where is_active order by sort_order');

  // Card rows, plus the two axes the filters need, denormalised into arrays so
  // the preview data layer can filter in memory the way SQL would.
  const products = await rows(`
    select p.id, p.slug, p.name_ar, p.short_pitch_ar, p.cover_url, p.moq,
           p.price_at_moq, p.price_from, p.for_corporate, p.for_individual,
           p.is_available, p.is_featured, p.category_id, p.sort_order, p.created_at,
           p.search_key,
           p.material_ar, p.dimensions_ar, p.weight_g, p.capacity_ml, p.paper_gsm,
           p.page_count, p.usb_capacity_gb, p.battery_mah, p.pack_size,
           p.warranty_months, p.origin_ar, p.is_eco,
           c.slug as category_slug,
           coalesce((select array_agg(o.slug) from product_occasions po
                       join occasions o on o.id = po.occasion_id
                      where po.product_id = p.id), '{}') as occasion_slugs,
           coalesce((select array_agg(m.method_code) from product_print_methods m
                      where m.product_id = p.id), '{}') as method_codes
      from products p join categories c on c.id = p.category_id
     where p.is_published
     order by p.is_featured desc, p.sort_order`);

  // The detail shape, built the same way PostgREST would embed it.
  const details = await rows(`
    select p.slug, (to_jsonb(p) || jsonb_build_object(
      'categories', (select to_jsonb(c) - 'blurb_ar' from categories c where c.id = p.category_id),
      'product_price_tiers', coalesce((select jsonb_agg(jsonb_build_object(
          'min_qty', t.min_qty, 'unit_price', t.unit_price) order by t.min_qty)
        from product_price_tiers t where t.product_id = p.id), '[]'::jsonb),
      'product_print_methods', coalesce((select jsonb_agg(
          to_jsonb(pm) || jsonb_build_object('print_methods', to_jsonb(m))
          order by m.sort_order)
        from product_print_methods pm join print_methods m on m.code = pm.method_code
        where pm.product_id = p.id), '[]'::jsonb),
      'print_positions', coalesce((select jsonb_agg(to_jsonb(pos) order by pos.sort_order)
        from print_positions pos where pos.product_id = p.id), '[]'::jsonb),
      'product_option_groups', coalesce((select jsonb_agg(
          to_jsonb(g) || jsonb_build_object('product_option_items',
            coalesce((select jsonb_agg(to_jsonb(i) order by i.sort_order)
              from product_option_items i where i.group_id = g.id), '[]'::jsonb))
          order by g.sort_order)
        from product_option_groups g where g.product_id = p.id), '[]'::jsonb),
      'product_images', coalesce((select jsonb_agg(to_jsonb(im) order by im.sort_order)
        from product_images im where im.product_id = p.id), '[]'::jsonb)
    )) as row
      from products p where p.is_published`);

  const specsByCategory = {};
  for (const c of categories) {
    specsByCategory[c.id] = await rows('select * from specs_for_category($1)', [c.id]);
  }

  // The price book per product — the same jsonb the configurator gets from the
  // RPC in production, produced by the same function. The preview therefore
  // exercises the real quote_product(), not a hand-written approximation of it.
  const books = Object.fromEntries(
    (
      await rows(`select p.slug, public.quote_product(p.id) as book
                    from products p where p.is_published`)
    ).map((r) => [r.slug, r.book])
  );

  const payload = {
    generatedFrom: 'supabase/migrations + supabase/seed.sql',
    settings,
    categories,
    occasions,
    methods,
    products,
    details: Object.fromEntries(details.map((d) => [d.slug, d.row])),
    specsByCategory,
    books,
  };

  mkdirSync(dirname(OUT), { recursive: true });
  writeFileSync(OUT, JSON.stringify(payload, null, 1), 'utf8');
  console.log(
    `wrote ${OUT}\n  ${products.length} products · ${categories.length} categories · ` +
      `${occasions.length} occasions · ${methods.length} print methods`
  );
} finally {
  await client.end().catch(() => {});
  await pg.stop().catch(() => {});
}
