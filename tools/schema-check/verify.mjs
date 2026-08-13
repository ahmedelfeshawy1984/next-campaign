// Applies the real migrations and seed to a throwaway Postgres, then asserts
// the rules this system depends on:
//
//   * the spec catalogue is honest — every spec_defs.key is a real column on
//     products. Without this, a typo produces a filter control that silently
//     matches nothing and a form field that saves nowhere, and nothing
//     complains.
//   * the price ladder cannot be typed into a silent overcharge, and the
//     denormalised price_at_moq / price_from agree with the tier table after
//     insert, update AND delete — they are maintained by a trigger, and a
//     trigger can drift where a generated column cannot.
//   * the anonymous read surface is exactly the shop window, from both sides.
//   * no cost price, supplier or margin has crept onto an anon-readable table.
//   * SQL and JavaScript fold Arabic and normalise phones identically. Two
//     implementations are only acceptable when a test proves they are one.
//
// Run after ANY change under supabase/:
//   G:\dev-tools\node\node.exe tools/schema-check/verify.mjs
import { fileURLToPath } from 'node:url';
import { dirname, resolve, join } from 'node:path';
import { readFileSync, readdirSync } from 'node:fs';
import EmbeddedPostgresMod from 'embedded-postgres';

import {
  AUTH_STUB,
  clearDataDir,
  makeChecker,
  asAnon,
  asUser,
  expectBlocked,
  expectBlockedAnon,
} from './stub.mjs';

// The single source of truth for both helpers, shared with the web app rather
// than re-implemented here. They are authored as plain .js with JSDoc types so
// that Next.js (allowJs + checkJs) and this harness can both import the exact
// same file — a TypeScript-only copy would need a build step here, and the
// moment the harness compiles its own copy it stops testing the app's.
import { normalizePhone, isEgMobile } from '../../web/lib/phone.js';
import { foldArabic } from '../../web/lib/arabic.js';
import { computeQuote } from '../../web/lib/pricing.js';
import { clinicChecks } from './clinic.mjs';

const MANAGER_ID  = '11111111-1111-1111-1111-111111111111';
const CUSTOMER_ID = '22222222-2222-2222-2222-222222222222';

const here = dirname(fileURLToPath(import.meta.url));
const EmbeddedPostgres = EmbeddedPostgresMod.default ?? EmbeddedPostgresMod;
const MIG  = resolve(here, '../../supabase/migrations');
const SEED = resolve(here, '../../supabase/seed.sql');

const { results, check } = makeChecker();

const dataDir = join(here, 'pgdata');
clearDataDir(dataDir);

const pg = new EmbeddedPostgres({
  databaseDir: dataDir,
  user: 'postgres',
  password: 'postgres',
  port: 54997,
  persistent: false,
  // Supabase runs UTF8; the Windows default of WIN1252 cannot store Arabic,
  // and every label in this database is Arabic. Without this flag every other
  // check here passes while testing a database that could not hold the data.
  initdbFlags: ['--encoding=UTF8', '--locale=C'],
});

console.log('initialising postgres...');
try {
  await pg.initialise();
  await pg.start();
} catch (e) {
  // clearDataDir removes the directory a killed run left behind, but it cannot
  // remove the PROCESS that is still holding it. On Windows that surfaces as
  // "pre-existing shared memory block is still in use" wrapped in twenty lines
  // of stack trace, which reads like a broken harness rather than leftover
  // rubbish. Say what to do instead.
  if (String(e.message).includes('shared memory block')) {
    console.error(
      '\nA postgres from a previous run is still alive and holding this data directory.\n' +
        'Stop it and run again:\n' +
        '  powershell -c "Get-Process postgres | Stop-Process -Force"\n'
    );
    process.exit(1);
  }
  throw e;
}
console.log('started.\n');

const client = pg.getPgClient();
await client.connect();

const one = async (sql, params = []) => (await client.query(sql, params)).rows[0];

try {
  await client.query(AUTH_STUB);
  check('auth stub created', true);

  // Read the directory rather than keep a list here: a hand-written list
  // silently skips every migration added after it was written, and reports a
  // clean run while testing none of the new SQL.
  const files = readdirSync(MIG).filter((f) => f.endsWith('.sql')).sort();
  check('migrations found', files.length > 0, `${files.length} files`);

  for (const f of files) {
    try {
      await client.query(readFileSync(join(MIG, f), 'utf8'));
      check(`migration ${f}`, true);
    } catch (e) {
      check(`migration ${f}`, false, e.message);
      throw e;
    }
  }

  await client.query(readFileSync(SEED, 'utf8'));
  check('seed applied', true);

  await client.query(
    `insert into auth.users (id, email, raw_user_meta_data)
     values ($1, 'manager@nextcampaign.app',
             '{"role":"manager","full_name":"المدير","phone":"01000000001"}'::jsonb),
            ($2, 'customer@nextcampaign.app',
             '{"role":"customer","full_name":"عميل","phone":"01000000002"}'::jsonb)`,
    [MANAGER_ID, CUSTOMER_ID]
  );
  const seededProfiles = await client.query(
    'select role from profiles where id = any($1::uuid[]) order by role',
    [[MANAGER_ID, CUSTOMER_ID]]
  );
  check(
    'the auth trigger mirrors a new user into profiles with its role',
    seededProfiles.rowCount === 2 &&
      seededProfiles.rows.map((r) => r.role).join(',') === 'customer,manager',
    seededProfiles.rows.map((r) => r.role).join(',')
  );

  // An anonymous sign-in has no name and no phone in its metadata. If
  // handle_new_user() cannot cope with that, every artwork upload dies at the
  // first step with an error the customer cannot read.
  await client.query(
    `insert into auth.users (id, email, raw_user_meta_data)
     values ('33333333-3333-3333-3333-333333333333', null, '{}'::jsonb)`
  );
  const anonProfile = await one(
    `select full_name, phone from profiles where id = '33333333-3333-3333-3333-333333333333'`
  );
  check(
    'an anonymous sign-in gets a profile with no phone and a placeholder name',
    !!anonProfile && anonProfile.phone === null && anonProfile.full_name === 'زائر',
    JSON.stringify(anonProfile)
  );

  // ---- encoding -----------------------------------------------------------

  const arabicRoundTrip = await one(
    `select name_ar from products where slug = 'mug-ceramic-white'`
  );
  check(
    'Arabic survives a round trip through the database',
    arabicRoundTrip?.name_ar === 'مج سيراميك أبيض',
    arabicRoundTrip?.name_ar
  );

  // ---- the catalogue arrived ----------------------------------------------

  for (const [table, min] of [
    ['categories', 10], ['occasions', 8], ['products', 20],
    ['print_methods', 10], ['fonts', 8], ['spec_defs', 10],
    ['product_price_tiers', 80], ['print_positions', 30],
    ['product_print_methods', 35], ['product_option_items', 40],
  ]) {
    const n = (await one(`select count(*)::int n from ${table}`)).n;
    check(`${table} seeded`, n >= min, `${n} rows (expected >= ${min})`);
  }

  // ---- the spec catalogue is honest ---------------------------------------

  // The highest-value assertion in this file. A spec_defs row whose key is not
  // a real column produces a filter that matches nothing and a form field that
  // saves nowhere — both silent.
  const orphanSpecs = await client.query(
    `select d.key from spec_defs d
      where not exists (
        select 1 from information_schema.columns c
         where c.table_schema = 'public' and c.table_name = 'products'
           and c.column_name = d.key
      )`
  );
  check(
    'every spec_defs.key is a real column on products',
    orphanSpecs.rowCount === 0,
    orphanSpecs.rows.map((r) => r.key).join(', ') || 'all keys resolve'
  );

  // The mirror of the above: a column the owner is meant to fill but that no
  // spec_defs row exposes is a column the admin form never renders.
  const unexposed = await client.query(
    `select c.column_name from information_schema.columns c
      where c.table_schema = 'public' and c.table_name = 'products'
        and c.column_name in ('material_ar','dimensions_ar','weight_g','capacity_ml',
                              'paper_gsm','page_count','usb_capacity_gb','battery_mah',
                              'pack_size','warranty_months','origin_ar','is_eco')
        and not exists (select 1 from spec_defs d where d.key = c.column_name)`
  );
  check(
    'every spec column is exposed by a spec_defs row',
    unexposed.rowCount === 0,
    unexposed.rows.map((r) => r.column_name).join(', ') || 'all columns exposed'
  );

  const enumSpecs = await client.query(`select key from spec_defs where kind = 'enum'`);
  if (enumSpecs.rowCount === 0) {
    check('no enum specs yet — option-legality check not applicable', true);
  } else {
    const illegal = await client.query(
      `select o.spec_key, o.value from spec_options o
        join spec_defs d on d.key = o.spec_key and d.kind = 'enum'
        join information_schema.columns c
          on c.table_schema = 'public' and c.table_name = 'products'
         and c.column_name = d.key
        where not exists (
          select 1 from pg_enum e
            join pg_type t on t.oid = e.enumtypid
           where t.typname = c.udt_name and e.enumlabel = o.value)`
    );
    check(
      'every enum spec_option is a value the column type accepts',
      illegal.rowCount === 0,
      illegal.rows.map((r) => `${r.spec_key}=${r.value}`).join(', ')
    );
  }

  // ---- spec scoping: the "empty means all" convention ----------------------

  const mugsCat = await one(`select id from categories where slug = 'mugs'`);
  const techCat = await one(`select id from categories where slug = 'tech'`);

  const mugSpecs = (
    await client.query('select key from specs_for_category($1)', [mugsCat.id])
  ).rows.map((r) => r.key);
  const techSpecs = (
    await client.query('select key from specs_for_category($1)', [techCat.id])
  ).rows.map((r) => r.key);

  check(
    'an unscoped spec applies to every category',
    mugSpecs.includes('material_ar') && techSpecs.includes('material_ar'),
    'material_ar'
  );
  check(
    'a scoped spec appears only in its own categories',
    mugSpecs.includes('capacity_ml') && !techSpecs.includes('capacity_ml') &&
      techSpecs.includes('battery_mah') && !mugSpecs.includes('battery_mah'),
    `mugs: ${mugSpecs.length} specs, tech: ${techSpecs.length} specs`
  );
  // The whole point of scoping. If this number creeps back up, the add-product
  // form has quietly become the sixty-field form again.
  check(
    'no category is asked for more than 10 specs',
    mugSpecs.length <= 10 && techSpecs.length <= 10,
    `mugs ${mugSpecs.length}, tech ${techSpecs.length}`
  );

  // ---- the price ladder ----------------------------------------------------

  const mug = await one(`select id, moq, price_at_moq, price_from from products
                          where slug = 'mug-ceramic-white'`);

  check(
    'price_at_moq is the rung at the cheapest legal quantity, not the cheapest rung',
    Number(mug.price_at_moq) === 75 && Number(mug.price_from) === 47,
    `at_moq=${mug.price_at_moq} from=${mug.price_from} moq=${mug.moq}`
  );

  // Boundaries. Off-by-one here is money.
  const b1 = await one(`select tier_unit_price($1,  99) p`, [mug.id]);
  const b2 = await one(`select tier_unit_price($1, 100) p`, [mug.id]);
  const b3 = await one(`select tier_unit_price($1, 101) p`, [mug.id]);
  check(
    'a quantity one below a tier boundary still pays the previous rung',
    Number(b1.p) === 75 && Number(b2.p) === 65 && Number(b3.p) === 65,
    `99=${b1.p} 100=${b2.p} 101=${b3.p}`
  );

  const below = await one(`select tier_unit_price($1, 1) p`, [mug.id]);
  check(
    'a quantity below every rung has no price at all, rather than a wrong one',
    below.p === null,
    String(below.p)
  );

  // The trigger, after each of the three shapes of change.
  await client.query(
    `insert into product_price_tiers (product_id, min_qty, unit_price) values ($1, 2000, 44)`,
    [mug.id]
  );
  let after = await one('select price_at_moq, price_from from products where id = $1', [mug.id]);
  check(
    'price_from follows an INSERT of a cheaper rung',
    Number(after.price_from) === 44 && Number(after.price_at_moq) === 75,
    `from=${after.price_from}`
  );

  await client.query(
    `update product_price_tiers set unit_price = 70 where product_id = $1 and min_qty = 36`,
    [mug.id]
  );
  after = await one('select price_at_moq from products where id = $1', [mug.id]);
  check(
    'price_at_moq follows an UPDATE of the MOQ rung',
    Number(after.price_at_moq) === 70,
    `at_moq=${after.price_at_moq}`
  );

  await client.query(
    `delete from product_price_tiers where product_id = $1 and min_qty = 2000`,
    [mug.id]
  );
  after = await one('select price_from from products where id = $1', [mug.id]);
  check(
    'price_from follows a DELETE — the case a generated column would have got free',
    Number(after.price_from) === 47,
    `from=${after.price_from}`
  );

  await client.query(`update product_price_tiers set unit_price = 75
                       where product_id = $1 and min_qty = 36`, [mug.id]);

  // Moving the MOQ moves which rung the card advertises.
  await client.query('update products set moq = 250 where id = $1', [mug.id]);
  after = await one('select price_at_moq from products where id = $1', [mug.id]);
  check(
    'price_at_moq is recomputed when MOQ moves',
    Number(after.price_at_moq) === 58,
    `at_moq=${after.price_at_moq}`
  );
  await client.query('update products set moq = 36 where id = $1', [mug.id]);

  // A rung that goes UP with quantity is a typo, never a decision.
  await client.query('begin');
  try {
    await client.query(
      `insert into product_price_tiers (product_id, min_qty, unit_price) values ($1, 3000, 200)`,
      [mug.id]
    );
    await client.query('commit');
    check('a rung that rises with quantity is refused', false, 'the insert succeeded');
  } catch (e) {
    await client.query('rollback');
    check(
      'a rung that rises with quantity is refused',
      String(e.message).includes('PRICE_LADDER_NOT_DESCENDING'),
      e.message.slice(0, 60)
    );
  }

  // Replacing a whole ladder passes through an invalid intermediate state.
  // The validation is deferred to commit precisely so this works.
  await client.query('begin');
  try {
    await client.query('delete from product_price_tiers where product_id = $1', [mug.id]);
    await client.query(
      `insert into product_price_tiers (product_id, min_qty, unit_price)
       values ($1,36,75),($1,100,65),($1,250,58),($1,500,52),($1,1000,47)`,
      [mug.id]
    );
    await client.query('commit');
    check('a whole ladder can be replaced in one transaction', true);
  } catch (e) {
    await client.query('rollback');
    check('a whole ladder can be replaced in one transaction', false, e.message.slice(0, 80));
  }

  // ---- the publish gate ----------------------------------------------------

  const cat = await one(`select id from categories where slug = 'desk'`);
  const draft = await one(
    `insert into products (slug, category_id, name_ar, moq)
     values ('harness-draft', $1, 'منتج تحت التجهيز', 10) returning id`,
    [cat.id]
  );

  await client.query('begin');
  try {
    await client.query('update products set is_published = true where id = $1', [draft.id]);
    await client.query('rollback');
    check('publishing a product with no pricing is refused', false, 'it published');
  } catch (e) {
    await client.query('rollback');
    check(
      'publishing a product with no pricing is refused',
      String(e.message).includes('PRICING_INCOMPLETE'),
      e.message.slice(0, 60)
    );
  }

  // Give it a tier and a method but NO position: still incomplete.
  await client.query(
    `insert into product_price_tiers (product_id, min_qty, unit_price) values ($1, 10, 50)`,
    [draft.id]
  );
  await client.query(
    `insert into product_print_methods (product_id, method_code) values ($1, 'uv')`,
    [draft.id]
  );
  await client.query('begin');
  try {
    await client.query('update products set is_published = true where id = $1', [draft.id]);
    await client.query('rollback');
    check('publishing a product with no print position is refused', false, 'it published');
  } catch (e) {
    await client.query('rollback');
    check('publishing a product with no print position is refused',
      String(e.message).includes('PRICING_INCOMPLETE'), e.message.slice(0, 60));
  }

  await client.query(
    `insert into print_positions (product_id, code, name_ar) values ($1, 'front', 'الوش')`,
    [draft.id]
  );
  await client.query('update products set is_published = true where id = $1', [draft.id]);
  check('a complete product publishes', true);

  // And once published it cannot be stripped back to unpriced.
  await client.query('begin');
  try {
    await client.query('delete from product_price_tiers where product_id = $1', [draft.id]);
    await client.query('commit');
    check('a published product cannot lose the rung at its MOQ', false, 'the delete stuck');
  } catch (e) {
    // A deferred constraint that raises AT COMMIT has already aborted the
    // transaction; the tidy-up rollback is a no-op and Postgres says so.
    await client.query('rollback').catch(() => {});
    check(
      'a published product cannot lose the rung at its MOQ',
      String(e.message).includes('PRICING_INCOMPLETE'),
      e.message.slice(0, 60)
    );
  }

  // ---- every published product is actually orderable ------------------------

  const notOrderable = await client.query(
    `select slug from products p
      where p.is_published and not public.pricing_complete(p.id)`
  );
  check(
    'every published product has a rung at its MOQ, a method and a position',
    notOrderable.rowCount === 0,
    notOrderable.rows.map((r) => r.slug).join(', ') || 'all orderable'
  );

  const noCover = await client.query(
    `select count(*)::int n from products where is_published and cover_url is null`
  );
  // Not a failure yet — the seed ships without photographs — but it IS the
  // thing that silently breaks the WhatsApp preview, so it is counted out loud
  // rather than discovered by the owner in front of a client.
  check(
    'published products without a cover image are counted (og:image depends on it)',
    true,
    `${noCover.rows[0].n} of ${(await one('select count(*)::int n from products where is_published')).n} have no cover yet`
  );

  // ---- one badge per card ---------------------------------------------------

  await expectBlocked(
    client, check, MANAGER_ID,
    `insert into product_occasions (product_id, occasion_id, is_primary)
     select p.id, o.id, true from products p, occasions o
      where p.slug = 'giftbox-ramadan' and o.slug = 'eid'`,
    'a product cannot carry two primary occasion badges'
  );

  // ---- SQL and JavaScript agree --------------------------------------------

  const spellings = [
    '01001234567', '0100 123 4567', '+20 100 123 4567', '00201001234567',
    '1001234567', '٠١٠٠١٢٣٤٥٦٧',
  ];
  let phoneAgree = true;
  let phoneDetail = '';
  for (const s of spellings) {
    const sqlAnswer = (await one('select normalize_phone($1) p', [s])).p;
    const jsAnswer = normalizePhone(s);
    if (sqlAnswer !== jsAnswer || sqlAnswer !== '01001234567') {
      phoneAgree = false;
      phoneDetail += `${s}: sql=${sqlAnswer} js=${jsAnswer}; `;
    }
  }
  check(
    'SQL and JavaScript normalise all six phone spellings to the same number',
    phoneAgree,
    phoneDetail || 'all six → 01001234567'
  );

  const mobileCases = [['01001234567', true], ['01301234567', false], ['0100123456', false]];
  let mobileAgree = true;
  for (const [raw, expected] of mobileCases) {
    const sqlAnswer = (await one('select is_eg_mobile($1) v', [raw])).v;
    if (sqlAnswer !== expected || isEgMobile(raw) !== expected) mobileAgree = false;
  }
  check('SQL and JavaScript agree on what an Egyptian mobile number is', mobileAgree);

  const foldCases = ['أبيض', 'مِج سِيرَامِيك', 'أجندة', 'ميدالية'];
  let foldAgree = true;
  let foldDetail = '';
  for (const s of foldCases) {
    const sqlAnswer = (await one('select fold_arabic($1) v', [s])).v;
    if (sqlAnswer !== foldArabic(s)) {
      foldAgree = false;
      foldDetail += `${s}: sql=${sqlAnswer} js=${foldArabic(s)}; `;
    }
  }
  check(
    'SQL and JavaScript fold Arabic identically',
    foldAgree,
    foldDetail || foldCases.map((s) => `${s}→${foldArabic(s)}`).join(' ')
  );

  // The fold is only worth anything if the stored column used it too.
  const found = await client.query(
    `select slug from products where search_key like '%' || fold_arabic($1) || '%'`,
    ['أبيض']
  );
  check(
    'searching the folded term finds the product whose name carried the hamza',
    found.rows.some((r) => r.slug === 'mug-ceramic-white'),
    `${found.rowCount} match(es)`
  );

  // ---- the anonymous read surface ------------------------------------------

  await asAnon(client, async () => {
    const pub = await client.query(`select count(*)::int n from products`);
    check('anon sees the published catalogue', pub.rows[0].n >= 20, `${pub.rows[0].n} products`);

    const drafts = await client.query(
      `select count(*)::int n from products where slug = 'harness-hidden'`);
    check('anon sees no drafts', drafts.rows[0].n === 0);

    const tiers = await client.query('select count(*)::int n from product_price_tiers');
    check('anon can read the price ladder', tiers.rows[0].n > 0, `${tiers.rows[0].n} rungs`);

    const methods = await client.query('select count(*)::int n from print_methods');
    check('anon can read the print methods', methods.rows[0].n >= 10);
  });

  // A draft's children must be invisible too, or the price of an unannounced
  // product leaks through a table nobody thought of as secret.
  const hidden = await one(
    `insert into products (slug, category_id, name_ar, moq)
     values ('harness-hidden', $1, 'مسودة', 5) returning id`, [cat.id]
  );
  await client.query(
    `insert into product_price_tiers (product_id, min_qty, unit_price) values ($1, 5, 999)`,
    [hidden.id]
  );
  await asAnon(client, async () => {
    const leak = await client.query(
      'select count(*)::int n from product_price_tiers where product_id = $1', [hidden.id]);
    check('anon cannot read the price ladder of a draft product', leak.rows[0].n === 0);
  });

  await expectBlockedAnon(client, check,
    'select * from product_private', 'anon cannot read product_private at all');
  await expectBlockedAnon(client, check,
    'select * from profiles', 'anon cannot read profiles at all');
  await expectBlockedAnon(client, check,
    `update products set price_at_moq = 1`, 'anon cannot rewrite a price');
  await expectBlockedAnon(client, check,
    `insert into products (slug, category_id, name_ar) values ('x', gen_random_uuid(), 'x')`,
    'anon cannot add a product');
  await expectBlockedAnon(client, check,
    `insert into product_price_tiers (product_id, min_qty, unit_price)
     values (gen_random_uuid(), 1, 1)`,
    'anon cannot add a price rung');

  // A signed-in customer is not a manager.
  //
  // NOTE THE SHAPE OF THESE TWO. `authenticated` HAS the table grant — that is
  // how Supabase ships — so the refusal is RLS filtering, not a permission
  // error. An UPDATE that matches no policy affects ZERO ROWS AND RAISES
  // NOTHING; a SELECT returns an empty set. Asserting "it throws" here passes
  // for the wrong reason on the anon checks above and fails here, which is
  // exactly the trap stub.mjs warns about. Assert the row count instead.
  await asUser(client, CUSTOMER_ID, async () => {
    const upd = await client.query('update product_price_tiers set unit_price = 1');
    check(
      'an ordinary signed-in user changes no prices (RLS filters, it does not raise)',
      upd.rowCount === 0,
      `${upd.rowCount} rows updated`
    );

    const priv = await client.query('select * from product_private');
    check(
      'an ordinary signed-in user reads no cost prices',
      priv.rowCount === 0,
      `${priv.rowCount} rows returned`
    );

    const ins = await client.query(
      `insert into product_price_tiers (product_id, min_qty, unit_price)
       select id, 7777, 1 from products where slug = 'mug-ceramic-white'
       on conflict do nothing`
    ).then(() => 'inserted').catch((e) => e.code);
    check(
      'an ordinary signed-in user cannot add a price rung',
      ins !== 'inserted',
      `blocked (${ins})`
    );
  });

  // And prove the manager path is not blocked by the same policy — a rule that
  // stops everyone is not a rule, it is an outage.
  await asUser(client, MANAGER_ID, async () => {
    const upd = await client.query(
      `update product_price_tiers set unit_price = unit_price
        where min_qty = 36`);
    check('a manager can edit prices', upd.rowCount > 0, `${upd.rowCount} rows`);
  });

  await asUser(client, MANAGER_ID, async () => {
    const seen = await client.query(
      `select count(*)::int n from products where slug = 'harness-hidden'`);
    check('a manager sees drafts', seen.rows[0].n === 1);
  });

  // ---- the private-column rule, made self-policing --------------------------

  // This converts a rule that otherwise lives in a comment and in somebody's
  // memory into a check that fails the build. A promotional-gifts business is
  // entirely about margin, so this rule WILL be tested by a future edit.
  const leaked = await client.query(
    `select distinct t.table_name, c.column_name
       from information_schema.role_table_grants t
       join information_schema.columns c
         on c.table_schema = t.table_schema and c.table_name = t.table_name
      where t.grantee = 'anon' and t.privilege_type = 'SELECT'
        and t.table_schema = 'public'
        and c.column_name ~ '(cost|supplier|margin|profit|purchase|wholesale)'`
  );
  check(
    'no cost, supplier or margin column is readable by anon',
    leaked.rowCount === 0,
    leaked.rows.map((r) => `${r.table_name}.${r.column_name}`).join(', ') || 'clean'
  );

  // And the inverse: the private table must not have drifted into the grant
  // list by someone adding it to the `grant select` block.
  const privateGrant = await client.query(
    `select 1 from information_schema.role_table_grants
      where grantee = 'anon' and table_schema = 'public'
        and table_name in ('product_private','profiles')`
  );
  check('product_private and profiles carry no anon grant', privateGrant.rowCount === 0);

  // ---- storage --------------------------------------------------------------

  const buckets = await client.query(
    `select id, public, file_size_limit, allowed_mime_types from storage.buckets order by id`);
  const byId = Object.fromEntries(buckets.rows.map((r) => [r.id, r]));
  check(
    'the product media bucket is public and the customer artwork bucket is not',
    byId['product-media']?.public === true && byId['customer-artwork']?.public === false,
    buckets.rows.map((r) => `${r.id}:${r.public}`).join(' ')
  );
  check(
    'artwork uploads are allowed up to 20 MB — print files are not avatars',
    Number(byId['customer-artwork']?.file_size_limit) === 20971520,
    String(byId['customer-artwork']?.file_size_limit)
  );
  check(
    'the artwork bucket has no mime whitelist (a strict one rejects genuine .ai files)',
    byId['customer-artwork']?.allowed_mime_types == null,
    String(byId['customer-artwork']?.allowed_mime_types)
  );

  // ---- the position/method convention ---------------------------------------

  // "Zero rows in position_print_methods means every method the product
  // supports". Asserted as data here; the resolver that reads it arrives with
  // quote_product() in P2 and gets its own check then.
  const overrides = await one(
    `select count(*)::int n from position_print_methods`);
  const positions = await one(`select count(*)::int n from print_positions`);
  check(
    'the override table stays the exception, not the rule',
    overrides.n > 0 && overrides.n < positions.n / 4,
    `${overrides.n} overrides for ${positions.n} positions`
  );

  // ---- the pricing engine ---------------------------------------------------

  const asP = (v) => Math.round(Number(v ?? 0) * 100);
  const sameErrors = (a, b) =>
    [...new Set(a)].sort().join('|') === [...new Set(b)].sort().join('|');

  const quoteSql = async (productId, sel) =>
    (
      await one('select public.price_quote($1,$2,$3,$4,$5::uuid[],$6::uuid[]) q', [
        productId,
        sel.qty,
        sel.methodCode,
        sel.colors,
        sel.positionIds,
        sel.optionItemIds,
      ])
    ).q;

  const bookFor = async (productId) =>
    (await one('select public.quote_product($1) b', [productId])).b;

  // The price book is what the browser prices against. If it does not resolve
  // the position/method convention, the configurator offers combinations the
  // workshop cannot make.
  const mugBook = await bookFor(mug.id);
  check(
    'quote_product returns a complete price book',
    mugBook &&
      mugBook.tiers.length >= 5 &&
      mugBook.methods.length >= 2 &&
      mugBook.positions.length >= 2 &&
      mugBook.fonts.length >= 5,
    `${mugBook?.tiers.length} tiers · ${mugBook?.methods.length} methods · ` +
      `${mugBook?.positions.length} positions · ${mugBook?.fonts.length} fonts`
  );

  // "Empty means all": the mug's positions carry no override rows, so every
  // method the product supports must come back on every position.
  const mugFront = mugBook.positions.find((p) => p.code === 'front');
  check(
    'a position with no override rows offers every method the product supports',
    mugFront.methods.length === mugBook.methods.length,
    `${mugFront.methods.length} of ${mugBook.methods.length}`
  );

  // …and the one product that DOES have an override row is restricted to it.
  const travel = await one(`select id from products where slug = 'mug-travel-steel'`);
  const travelBook = await bookFor(travel.id);
  const travelBody = travelBook.positions.find((p) => p.code === 'body');
  check(
    'a position WITH override rows offers only those methods',
    travelBody.methods.length === 1 && travelBody.methods[0].code === 'uv',
    travelBody.methods.map((m) => m.code).join(',')
  );
  check(
    'an override narrows the printable area for that method',
    Number(travelBody.methods[0].area_w_mm) === 40,
    `${travelBody.methods[0].area_w_mm} mm (position itself is ${travelBody.area_w_mm} mm)`
  );

  // ---- golden cases. Each one is a specific way to lose money. --------------

  const golden = [
    {
      name: 'a quantity one below a boundary pays the previous rung, end to end',
      sel: { qty: 99, methodCode: 'sublimation', colors: 1, positionIds: [], optionItemIds: [] },
      expect: (q) => asP(q.unit_price) === 7500,
    },
    {
      name: 'and one piece more drops a rung',
      sel: { qty: 100, methodCode: 'sublimation', colors: 1, positionIds: [], optionItemIds: [] },
      expect: (q) => asP(q.unit_price) === 6500,
    },
    {
      name: 'a spot method charges per extra colour, per piece',
      sel: { qty: 100, methodCode: 'screen', colors: 3, positionIds: [], optionItemIds: [] },
      // screen on the mug: unit_addon 0, addon_per_color 2 → (3-1) * 2 = 4
      expect: (q) => asP(q.method_addon) === 400,
    },
    {
      name: 'one colour on a spot method costs no extra',
      sel: { qty: 100, methodCode: 'screen', colors: 1, positionIds: [], optionItemIds: [] },
      expect: (q) => asP(q.method_addon) === 0,
    },
    {
      name: 'a single-tone method ignores the colour count entirely',
      sel: { qty: 100, methodCode: 'sublimation', colors: 4, positionIds: [], optionItemIds: [] },
      expect: (q) => q.colors === 1 && asP(q.method_addon) === 0,
    },
  ];

  for (const g of golden) {
    const q = await quoteSql(mug.id, g.sel);
    check(g.name, g.expect(q), `unit=${q.unit_price} addon=${q.method_addon} colors=${q.colors}`);
  }

  // Setup fees: one per position, waived at exactly the threshold (>=, not >).
  const frontId = mugFront.id;
  const backId = mugBook.positions.find((p) => p.code === 'back').id;

  const oneP = await quoteSql(mug.id, {
    qty: 100, methodCode: 'screen', colors: 2, positionIds: [frontId], optionItemIds: [],
  });
  const twoP = await quoteSql(mug.id, {
    qty: 100, methodCode: 'screen', colors: 2, positionIds: [frontId, backId], optionItemIds: [],
  });
  check(
    'two print positions are charged two setup fees',
    asP(twoP.setup_total) === 2 * asP(oneP.setup_total) && asP(oneP.setup_total) > 0,
    `one=${oneP.setup_total} two=${twoP.setup_total}`
  );
  check(
    'a per-colour cliché multiplies by the colour count',
    // screen on the mug: setup_fee 150, per_color true, 2 colours → 300
    asP(oneP.setup_total) === 30000,
    String(oneP.setup_total)
  );

  const atWaiver = await quoteSql(mug.id, {
    qty: 500, methodCode: 'screen', colors: 2, positionIds: [frontId], optionItemIds: [],
  });
  const belowWaiver = await quoteSql(mug.id, {
    qty: 499, methodCode: 'screen', colors: 2, positionIds: [frontId], optionItemIds: [],
  });
  check(
    'the cliché waiver fires at EXACTLY the threshold, not one above it',
    asP(atWaiver.setup_total) === 0 && asP(belowWaiver.setup_total) > 0,
    `499 → ${belowWaiver.setup_total}, 500 → ${atWaiver.setup_total}`
  );

  // Refusals the configurator has to be able to EXPLAIN rather than just fail.
  //
  // These are the reason price_quote returns codes instead of raising: the
  // picker has to say "screen printing needs at least 50" while the customer is
  // still choosing, and an exception can only say no.
  const tshirt = await one(`select id from products where slug = 'tshirt-cotton-round'`);

  const refusals = [
    ['QTY_BELOW_MOQ', mug.id,
      { qty: 10, methodCode: 'sublimation', colors: 1, positionIds: [], optionItemIds: [] }],
    ['METHOD_NOT_SUPPORTED', mug.id,
      { qty: 100, methodCode: 'embroidery', colors: 1, positionIds: [], optionItemIds: [] }],
    ['TOO_MANY_COLORS', mug.id,
      { qty: 100, methodCode: 'screen', colors: 9, positionIds: [], optionItemIds: [] }],
    // The t-shirt, not the mug: its MOQ is 24 but screen printing needs 50, so
    // this isolates the method floor from the product floor. On the mug the two
    // are both 36 and the case cannot be expressed at all.
    ['QTY_BELOW_METHOD_MIN', tshirt.id,
      { qty: 30, methodCode: 'screen', colors: 1, positionIds: [], optionItemIds: [] }],
    ['POSITION_NOT_ON_PRODUCT', mug.id,
      { qty: 100, methodCode: 'sublimation', colors: 1, positionIds: [travelBody.id], optionItemIds: [] }],
  ];
  for (const [code, productId, sel] of refusals) {
    const q = await quoteSql(productId, sel);
    check(`price_quote reports ${code}`, (q.errors ?? []).includes(code), (q.errors ?? []).join(','));
  }

  // And the mirror: a method floor that IS met must not report anything.
  const clean = await quoteSql(tshirt.id, {
    qty: 50, methodCode: 'screen', colors: 1, positionIds: [], optionItemIds: [],
  });
  check(
    'a quantity that meets both floors reports no error at all',
    clean.ok === true,
    (clean.errors ?? []).join(',') || 'clean'
  );

  // ---- SQL ↔ JavaScript parity. The check that makes two implementations
  //      acceptable at all. -----------------------------------------------

  // Seeded, so a failure is reproducible rather than "it went red once".
  let seed = 20260810;
  const rnd = () => {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed / 0x7fffffff;
  };
  const pick = (arr) => arr[Math.floor(rnd() * arr.length)];

  const fuzzProducts = await client.query(
    `select id, slug from products where is_published order by slug`
  );

  let compared = 0;
  let mismatch = null;

  for (const row of fuzzProducts.rows) {
    const book = await bookFor(row.id);
    if (!book || !book.methods.length) continue;

    for (let i = 0; i < Math.ceil(200 / fuzzProducts.rowCount); i++) {
      const method = pick(book.methods);
      const positions = book.positions.filter(() => rnd() < 0.5).slice(0, book.max_positions);
      const options = book.option_groups
        .map((g) => (g.items.length && rnd() < 0.7 ? pick(g.items) : null))
        .filter(Boolean);

      const sel = {
        qty: Math.max(1, Math.floor(rnd() * 1400)),
        methodCode: method.code,
        colors: 1 + Math.floor(rnd() * 5),
        positionIds: positions.map((p) => p.id),
        optionItemIds: options.map((o) => o.id),
      };

      const sql = await quoteSql(row.id, sel);
      const js = computeQuote(book, sel);
      compared++;

      const fields = [
        ['unit_price', 'unitPrice'],
        ['subtotal', 'subtotal'],
        ['setup_total', 'setupTotal'],
        ['pre_vat', 'preVat'],
        ['vat_amount', 'vatAmount'],
        ['total', 'total'],
      ];
      for (const [s, j] of fields) {
        if (asP(sql[s]) !== js[j]) {
          mismatch = `${row.slug} ${JSON.stringify(sel)} ${s}: sql=${asP(sql[s])} js=${js[j]}`;
          break;
        }
      }
      if (!mismatch && !sameErrors(sql.errors ?? [], js.errors)) {
        mismatch = `${row.slug} ${JSON.stringify(sel)} errors: sql=[${sql.errors}] js=[${js.errors}]`;
      }
      if (mismatch) break;
    }
    if (mismatch) break;
  }

  check(
    'SQL and JavaScript price every random selection identically, to the piastre',
    mismatch === null,
    mismatch ?? `${compared} selections across ${fuzzProducts.rowCount} products`
  );

  // VAT on and off, both engines.
  await client.query('begin');
  try {
    await client.query('update site_settings set prices_include_vat = true where id');
    const bookInc = await bookFor(mug.id);
    const sel = {
      qty: 250, methodCode: 'screen', colors: 2, positionIds: [frontId], optionItemIds: [],
    };
    const sqlInc = await quoteSql(mug.id, sel);
    const jsInc = computeQuote(bookInc, sel);
    check(
      'VAT-inclusive pricing adds nothing, in both engines',
      asP(sqlInc.vat_amount) === 0 &&
        jsInc.vatAmount === 0 &&
        asP(sqlInc.total) === jsInc.total,
      `both ${jsInc.total} piastres`
    );
  } finally {
    await client.query('rollback');
  }

  const vatSel = {
    qty: 250, methodCode: 'screen', colors: 2, positionIds: [frontId], optionItemIds: [],
  };
  const vatQ = await quoteSql(mug.id, vatSel);
  check(
    'VAT-exclusive pricing adds exactly the configured rate',
    asP(vatQ.vat_amount) === Math.round((asP(vatQ.pre_vat) * 1400) / 10000),
    `pre=${vatQ.pre_vat} vat=${vatQ.vat_amount} rate=${vatQ.vat_rate}`
  );

  // Anon has to be able to price a product — that is the point of publishing
  // prices at all.
  await asAnon(client, async () => {
    const b = await client.query('select public.quote_product($1) b', [mug.id]);
    const q = await client.query(
      'select public.price_quote($1,$2,$3,$4,$5::uuid[],$6::uuid[]) q',
      [mug.id, 100, 'sublimation', 1, [], []]
    );
    check(
      'anon can read a price book and price a configuration',
      !!b.rows[0].b && q.rows[0].q?.ok === true,
      `ok=${q.rows[0].q?.ok}`
    );
  });

  // A draft must not be priceable, or an unannounced product leaks through the
  // RPC that the catalogue policy was carefully written to hide.
  await asAnon(client, async () => {
    const b = await client.query('select public.quote_product($1) b', [hidden.id]);
    check('anon cannot get a price book for a draft product', b.rows[0].b === null);
  });

  // ---- orders ---------------------------------------------------------------

  // asUser() from stub.mjs rolls back, which is exactly right for "can this
  // person do X" but wrong for a SEQUENCE: an order cannot be moved new →
  // contacted → cancelled if every move is undone before the next one. That is
  // why "a cancelled order is a dead end" first passed for the wrong reason —
  // the order was still 'new'. This variant keeps the writes.
  const asUserCommitted = async (uid, fn) => {
    await client.query('set role authenticated');
    await client.query(`set "request.jwt.claim.sub" = '${uid}'`);
    try {
      return await fn();
    } finally {
      await client.query('reset "request.jwt.claim.sub"');
      await client.query('reset role');
    }
  };

  const orderPayload = (over = {}) => ({
    customer_kind: 'company',
    contact_name: 'شركة الاختبار',
    contact_phone: '01001234567',
    company_name: 'Test Co',
    governorate: 'القاهرة',
    ip_confirmed: true,
    lines: [
      {
        product_id: mug.id,
        qty: 250,
        method_code: 'screen',
        colors: 2,
        position_ids: [frontId],
        option_item_ids: [],
        texts: [{ slot: 1, content: 'شركة الاختبار', font_key: 'cairo' }],
        asset_paths: [],
      },
    ],
    ...over,
  });

  const placeOrder = async (payload) =>
    (await one('select public.create_order_request($1::jsonb) r', [JSON.stringify(payload)])).r;

  const order = await placeOrder(orderPayload({ client_total: 17442 }));
  check(
    'an order lands with a code a human can say on the phone',
    /^NC-\d{5}$/.test(order.code ?? ''),
    order.code
  );
  check(
    'the server computes the total itself — 250 mugs, screen, 2 colours, one position',
    asP(order.total) === 1744200,
    `${order.total} (expected 17,442.00)`
  );

  const placed = await one(
    `select o.*, l.unit_price_at_request, l.product_name_ar, l.colors_count,
            (select count(*)::int from order_line_texts t where t.line_id = l.id) texts,
            (select count(*)::int from order_line_positions p where p.line_id = l.id) positions
       from order_requests o join order_request_lines l on l.request_id = o.id
      where o.id = $1`,
    [order.id]
  );
  check(
    'the line stores the words exactly as typed and the position it prints on',
    placed.texts === 1 && placed.positions === 1 && asP(placed.unit_price_at_request) === 6000,
    `unit=${placed.unit_price_at_request} texts=${placed.texts} positions=${placed.positions}`
  );
  check(
    'a matching client total raises no mismatch flag',
    placed.price_mismatch === false,
    `client=${placed.client_total}`
  );

  // SNAPSHOTS. The whole reason the line carries names and prices of its own.
  await client.query('begin');
  try {
    await client.query(
      `update product_price_tiers set unit_price = 999 where product_id = $1`, [mug.id]);
    await client.query(`update products set name_ar = 'اسم اتغير' where id = $1`, [mug.id]);
    const after = await one(
      `select l.unit_price_at_request, l.product_name_ar
         from order_request_lines l where l.request_id = $1`, [order.id]);
    check(
      'repricing and renaming a product does not rewrite an order already placed',
      asP(after.unit_price_at_request) === 6000 && after.product_name_ar === 'مج سيراميك أبيض',
      `${after.product_name_ar} @ ${after.unit_price_at_request}`
    );
  } finally {
    await client.query('rollback');
  }

  // A total that disagrees is FLAGGED, not refused: rejecting punishes a
  // customer who left a tab open across a price change.
  const stale = await placeOrder(orderPayload({ client_total: 15000 }));
  const staleRow = await one('select price_mismatch, client_total, total from order_requests where id = $1', [stale.id]);
  check(
    'a stale total is accepted and flagged rather than refused',
    staleRow.price_mismatch === true && asP(staleRow.total) === 1744200,
    `client=${staleRow.client_total} server=${staleRow.total}`
  );

  // ---- the refusals ---------------------------------------------------------

  const expectOrderRefused = async (label, payload, marker) => {
    try {
      await placeOrder(payload);
      check(label, false, 'the order was accepted');
    } catch (e) {
      check(label, String(e.message).includes(marker), e.message.slice(0, 70));
    }
  };

  await expectOrderRefused(
    'an order with no IP confirmation is refused',
    orderPayload({ ip_confirmed: false }), 'IP_NOT_CONFIRMED');
  await expectOrderRefused(
    'an order with a landline is refused',
    orderPayload({ contact_phone: '0223456789' }), 'PHONE_INVALID');
  await expectOrderRefused(
    'an order with no name is refused',
    orderPayload({ contact_name: '' }), 'NAME_REQUIRED');
  await expectOrderRefused(
    'an order with no lines is refused',
    orderPayload({ lines: [] }), 'NO_LINES');
  await expectOrderRefused(
    'an order whose line is below the MOQ is refused',
    orderPayload({ lines: [{ ...orderPayload().lines[0], qty: 5 }] }), 'LINE_INVALID');

  // Two placed already; the third succeeds and the fourth must not.
  await placeOrder(orderPayload());
  await expectOrderRefused(
    'the fourth order from one phone in an hour is refused',
    orderPayload(), 'RATE_LIMITED');

  // A different number is unaffected — a rule that stops everyone is an outage.
  const other = await placeOrder(orderPayload({ contact_phone: '01112223344' }));
  check('a different phone is not caught by the per-phone limit', !!other.code, other.code);

  // ---- artwork: the check that is easiest to forget -------------------------

  await asUser(client, CUSTOMER_ID, async () => {
    const path = `${CUSTOMER_ID}/logo.ai`;
    const up = await client.query(
      'select public.register_upload($1,$2,$3,$4,$5,$6) id',
      [path, 'logo.ai', 'application/pdf', 120000, null, null]
    );
    check('a .ai file registers even though the browser calls it a PDF', !!up.rows[0].id);
  });

  await expectBlocked(client, check, CUSTOMER_ID,
    `select public.register_upload('11111111-1111-1111-1111-111111111111/x.ai','x.ai','',10,null,null)`,
    'registering an upload under somebody else’s folder is refused');

  await expectBlocked(client, check, CUSTOMER_ID,
    `select public.register_upload('${CUSTOMER_ID}/virus.exe','virus.exe','',10,null,null)`,
    'registering an executable is refused');

  await expectBlocked(client, check, CUSTOMER_ID,
    `select public.register_upload('${CUSTOMER_ID}/huge.pdf','huge.pdf','',30000000,null,null)`,
    'registering a file over 20 MB is refused');

  // THE ONE. Claiming another customer's artwork by guessing its path.
  await expectBlocked(client, check, CUSTOMER_ID,
    `select public.create_order_request($1::jsonb)`,
    'attaching another customer’s artwork to your own order is refused',
    [JSON.stringify(orderPayload({
      contact_phone: '01223334455',
      lines: [{
        ...orderPayload().lines[0],
        asset_paths: ['11111111-1111-1111-1111-111111111111/secret-logo.ai'],
      }],
    }))]
  );

  await expectBlocked(client, check, CUSTOMER_ID,
    `select public.create_order_request($1::jsonb)`,
    'attaching a file that was never registered is refused',
    [JSON.stringify(orderPayload({
      contact_phone: '01223334466',
      lines: [{ ...orderPayload().lines[0], asset_paths: [`${CUSTOMER_ID}/never-registered.ai`] }],
    }))]
  );

  // And the happy path, so the rule is not simply "nothing works".
  let withArt = null;
  await asUserCommitted(CUSTOMER_ID, async () => {
    await client.query('select public.register_upload($1,$2,$3,$4,$5,$6)',
      [`${CUSTOMER_ID}/brand.ai`, 'brand.ai', 'application/postscript', 240000, 2000, 1200]);
    const r = await client.query('select public.create_order_request($1::jsonb) r', [
      JSON.stringify(orderPayload({
        contact_phone: '01555666777',
        lines: [{ ...orderPayload().lines[0], asset_paths: [`${CUSTOMER_ID}/brand.ai`] }],
      })),
    ]);
    withArt = r.rows[0].r;
  });

  // Read the assets back OUTSIDE the customer's role. This is what the first
  // version of the check got wrong: order_line_assets is manager-only, so a
  // signed-in customer selecting from it gets zero rows — the assertion failed
  // while the function was working perfectly. RLS filtering looks identical to
  // "it did not happen" unless you read as somebody allowed to see it.
  const assets = await client.query(
    `select a.storage_path, a.original_name, a.px_width, a.uploaded_by
       from order_line_assets a
       join order_request_lines l on l.id = a.line_id where l.request_id = $1`,
    [withArt.id]
  );
  check(
    'your own registered artwork attaches, with its real filename and dimensions',
    assets.rowCount === 1 &&
      assets.rows[0].original_name === 'brand.ai' &&
      assets.rows[0].px_width === 2000 &&
      assets.rows[0].uploaded_by === CUSTOMER_ID,
    `${assets.rowCount} row(s): ${assets.rows.map((r) => r.original_name).join(',') || 'none'}`
  );

  // ---- tracking without an account -----------------------------------------

  const good = await one('select public.order_status($1,$2) s', [order.id, '٠١٠٠١٢٣٤٥٦٧']);
  check(
    'the order reads back from the id plus the phone, in any spelling of it',
    good.s?.code === order.code,
    good.s?.code
  );
  const wrongPhone = await one('select public.order_status($1,$2) s', [order.id, '01111111111']);
  check('the id alone is not enough to read an order', wrongPhone.s === null);

  // ---- the status machine ---------------------------------------------------

  await expectBlocked(client, check, CUSTOMER_ID,
    `select public.set_order_status($1, 'contacted')`,
    'a customer cannot move an order forward', [order.id]);

  await asUserCommitted(MANAGER_ID, async () => {
    await client.query(`select public.set_order_status($1, 'contacted')`, [order.id]);
    const s = await client.query('select status from order_requests where id = $1', [order.id]);
    check('a manager can move new → contacted', s.rows[0].status === 'contacted');

    const events = await client.query(
      'select count(*)::int n from order_request_events where request_id = $1', [order.id]);
    check('every move writes an event, by trigger', events.rows[0].n >= 2, `${events.rows[0].n} events`);
  });

  await expectBlocked(client, check, MANAGER_ID,
    `select public.set_order_status($1, 'delivered')`,
    'skipping from contacted straight to delivered is refused', [order.id]);

  await expectBlocked(client, check, MANAGER_ID,
    `select public.set_order_status($1, 'cancelled')`,
    'cancelling without a reason is refused', [order.id]);

  await asUserCommitted(MANAGER_ID, async () => {
    await client.query(`select public.set_order_status($1,'cancelled',null,'العميل غيّر رأيه')`,
      [order.id]);
    const s = await client.query('select status, closed_at from order_requests where id = $1',
      [order.id]);
    check('cancelling with a reason works and stamps the closing time',
      s.rows[0].status === 'cancelled' && !!s.rows[0].closed_at);
  });

  await expectBlocked(client, check, MANAGER_ID,
    `select public.set_order_status($1, 'contacted')`,
    'a cancelled order is a dead end', [order.id]);

  // ---- the status machine cannot be walked around ---------------------------

  const machineOrder = await placeOrder(orderPayload({ contact_phone: '01098765432' }));
  await expectBlocked(client, check, MANAGER_ID,
    `update order_requests set status = 'delivered' where id = $1`,
    'even a MANAGER cannot set a status by direct UPDATE — only through the function',
    [machineOrder.id]);

  await asUserCommitted(MANAGER_ID, async () => {
    const note = await client.query(
      `update order_requests set manager_note = 'كلمته الساعة ٣' where id = $1`,
      [machineOrder.id]);
    check(
      'a manager can still edit the fields a human actually types',
      note.rowCount === 1,
      `${note.rowCount} row(s)`
    );
  });

  // ---- accounts and the admin surface ---------------------------------------

  const seededManager = await one(
    `select id, full_name from profiles where phone = '01000000000' and role = 'manager'`);
  check(
    'the first manager account exists so the owner can get in without SQL',
    !!seededManager,
    seededManager?.full_name
  );
  const authRow = await one(
    `select email, encrypted_password is not null pw, email_confirmed_at is not null confirmed,
            confirmation_token is not null tok
       from auth.users where email = public.email_for_phone('01000000000')`);
  check(
    'the seeded manager is a real signed-in-able auth user, not just a profile',
    authRow?.pw === true && authRow?.confirmed === true && authRow?.tok === true,
    `${authRow?.email} pw=${authRow?.pw} confirmed=${authRow?.confirmed} tokens=${authRow?.tok}`
  );

  await expectBlocked(client, check, CUSTOMER_ID,
    `select public.admin_create_user('01234567890','متسلل','manager','hunter2')`,
    'a customer cannot mint a manager');
  await expectBlockedAnon(client, check,
    `select public.create_account('01234567890','متسلل','hunter2','manager')`,
    'the private account body is unreachable from outside');
  await expectBlockedAnon(client, check,
    'select public.admin_dashboard()', 'anon cannot read the dashboard counters');

  await asUserCommitted(MANAGER_ID, async () => {
    const made = await client.query(
      `select public.admin_create_user('01112223333','موظف','customer','staff2026') id`);
    check('a manager can add staff', !!made.rows[0].id);

    const dash = await client.query('select public.admin_dashboard() d');
    check(
      'the dashboard counts what the owner opens the panel to see',
      typeof dash.rows[0].d?.new === 'number' && typeof dash.rows[0].d?.urgent === 'number',
      JSON.stringify(dash.rows[0].d)
    );
  });

  await expectBlocked(client, check, MANAGER_ID,
    `select public.admin_set_active($1, false)`,
    'a manager cannot switch themselves off and lock the shop out',
    [MANAGER_ID]);

  // Deleting a product that has been ordered would leave "how many of these
  // have we done?" unanswerable. Unpublishing is the real intent.
  await expectBlocked(client, check, MANAGER_ID,
    `select public.admin_delete_product($1)`,
    'a product that has been ordered cannot be deleted',
    [mug.id]);

  await asUserCommitted(MANAGER_ID, async () => {
    const cat = await client.query(`select id from categories where slug = 'desk'`);
    const fresh = await client.query(
      `insert into products (slug, category_id, name_ar, moq)
       values ('harness-deletable', $1, 'منتج للحذف', 1) returning id`, [cat.rows[0].id]);
    await client.query('select public.admin_delete_product($1)', [fresh.rows[0].id]);
    const gone = await client.query(
      `select count(*)::int n from products where slug = 'harness-deletable'`);
    check('a product nobody ordered can be deleted', gone.rows[0].n === 0);
  });

  // ---- orders are not part of the shop window -------------------------------

  await expectBlockedAnon(client, check,
    'select * from order_requests', 'anon cannot read orders at all');
  await expectBlockedAnon(client, check,
    'select * from order_line_assets', 'anon cannot read customer artwork rows');
  await expectBlockedAnon(client, check,
    'select * from customer_uploads', 'anon cannot read the upload log');

  await asUser(client, CUSTOMER_ID, async () => {
    const seen = await client.query('select count(*)::int n from order_requests');
    check('a signed-in customer reads no orders through the tables', seen.rows[0].n === 0);
  });

  // ---- the cleanup sweeps orphans and spares evidence ------------------------

  await asUserCommitted(CUSTOMER_ID, async () => {
    await client.query('select public.register_upload($1,$2,$3,$4,$5,$6)',
      [`${CUSTOMER_ID}/abandoned.png`, 'abandoned.png', 'image/png', 5000, 400, 400]);
  });
  await client.query(
    `update customer_uploads set created_at = now() - interval '30 days'
      where storage_path like '%abandoned.png'`);
  // …and age the attached one too, so the test proves the cleanup spares it for
  // the right reason rather than because it happens to be recent.
  await client.query(
    `update customer_uploads set created_at = now() - interval '30 days'
      where storage_path like '%brand.ai'`);

  const swept = await one('select public.cleanup_orphan_uploads(7) r');
  const stillThere = await one(
    `select count(*)::int n from customer_uploads where storage_path like '%brand.ai'`);
  const gone = await one(
    `select count(*)::int n from customer_uploads where storage_path like '%abandoned.png'`);
  check(
    'the cleanup removes artwork nobody ordered and keeps artwork somebody did',
    gone.n === 0 && stillThere.n === 1,
    `${JSON.stringify(swept.r)} · abandoned=${gone.n} attached=${stillThere.n}`
  );

  const assetsIntact = await one(
    `select count(*)::int n from order_line_assets where storage_path like '%brand.ai'`);
  check(
    'an order keeps its artwork row whatever happens to the upload log',
    assetsIntact.n === 1,
    `${assetsIntact.n} asset row(s)`
  );

  await expectBlockedAnon(client, check,
    'select public.cleanup_orphan_uploads(7)',
    'anon cannot run the cleanup');

  // ---- the function surface anon can reach, as a whole ----------------------

  // The general form of the bug that produced the check above: Postgres grants
  // EXECUTE on every new function to PUBLIC, so a `revoke ... from anon` is a
  // no-op unless it names public. That is invisible per-function and obvious
  // in a list. Anything not on this list is either a new RPC somebody forgot to
  // think about, or a private function that just became reachable.
  const EXPECTED_ANON_FUNCTIONS = [
    'create_order_request',
    'effective_max_colors',
    // Granted on purpose: the login screen turns a phone into the synthetic
    // address before calling signInWithPassword. Doing that fold in JavaScript
    // instead would put the domain in two places, and the day they drift
    // nobody can sign in. It is a pure string function and leaks nothing.
    'email_for_phone',
    'fold_arabic',
    'is_eg_mobile',
    'is_manager',
    'mark_whatsapp_sent',
    'method_uses_color_count',
    'normalize_phone',
    'order_status',
    'position_allows_method',
    'price_quote',
    'product_visible',
    'quote_product',
    'register_upload',
    'specs_for_category',
    'tier_unit_price',
  ];

  const anonFunctions = (
    await client.query(
      `select p.proname from pg_proc p
         join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and has_function_privilege('anon', p.oid, 'EXECUTE')
        order by p.proname`
    )
  ).rows.map((r) => r.proname);

  const unexpected = anonFunctions.filter((f) => !EXPECTED_ANON_FUNCTIONS.includes(f));
  const missing = EXPECTED_ANON_FUNCTIONS.filter((f) => !anonFunctions.includes(f));

  check(
    'anon can execute exactly the functions it is meant to and no others',
    unexpected.length === 0,
    unexpected.length ? `unexpected: ${unexpected.join(', ')}` : `${anonFunctions.length} functions`
  );
  check(
    'every function anon is meant to reach is actually reachable',
    missing.length === 0,
    missing.length ? `missing: ${missing.join(', ')}` : 'all present'
  );

  // ---- العيادة ---------------------------------------------------------------

  // In its own file: a separate schema with a separate threat model, and this
  // one was long enough already. See tools/schema-check/clinic.mjs for what it
  // asserts and why each assertion is there.
  await clinicChecks({ client, check, one, asUser, expectBlocked, expectBlockedAnon });

  // ---- this database belongs to THIS app ------------------------------------

  // A shared Supabase project caused three silent failures in a sibling
  // project, one of which screamed. These two assertions are what catch it.
  const roleValues = (
    await client.query(
      `select e.enumlabel v from pg_enum e join pg_type t on t.oid = e.enumtypid
        where t.typname = 'user_role' order by 1`)
  ).rows.map((r) => r.v);
  check(
    "user_role is this app's enum, not another app's",
    roleValues.includes('customer') && roleValues.includes('manager'),
    roleValues.join(',')
  );
  const ours = await one(
    `select count(*)::int n from information_schema.tables
      where table_schema = 'public' and table_name = 'product_price_tiers'`);
  check('product_price_tiers exists — this is the Next Campaign schema', ours.n === 1);
} catch (e) {
  // WITHOUT THIS BLOCK a throw halfway down runs `finally`, finds no recorded
  // failures and exits 0 — the harness reports a clean run having skipped every
  // check after the throw. That is the worst possible failure mode for a test
  // suite, and it happened: the pricing section died and 84/84 was printed.
  check('the harness ran to the end', false, `${e.message}`.slice(0, 200));
  console.error(e);
} finally {
  const failed = results.filter((r) => !r.ok);
  console.log(`\n${results.length - failed.length}/${results.length} passed`);
  if (failed.length) {
    console.log('\nFAILED:');
    for (const f of failed) console.log(`  - ${f.name}${f.detail ? ' -> ' + f.detail : ''}`);
  }
  await client.end().catch(() => {});
  await pg.stop().catch(() => {});
  process.exit(failed.length ? 1 : 0);
}
