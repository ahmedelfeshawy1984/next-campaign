// Builds supabase/SETUP-CLINIC-ONLY.sql — the clinic on a database of its own.
//
// WHY THIS EXISTS
//
// The clinic was built as a separate schema inside the shop's Supabase project,
// and the isolation that gives is real: anon holds no USAGE on `clinic`, and the
// harness proves it. But "the patients are in a different schema" and "the
// patients are in a different database" are not the same promise, and for a
// medical record the owner asked for the second one.
//
// WHAT IT DOES NOT DO IS COPY ANY SQL.
//
// The clinic's tables depend on seven things that live in the shop's `public`
// schema — the profiles table, the user_role enum, touch_updated_at(),
// fold_arabic(), normalize_phone(), create_account() and its two helpers. A
// hand-written second copy of those for the standalone bundle would be a second
// copy of fold_arabic() in particular, and the day the two disagree "احمد" stops
// finding "أحمد" in one deployment and nobody can see why.
//
// So the shared pieces are EXTRACTED from the same migration files the shop
// installs, delimited by `-- >>> shared-with-clinic` markers. One source, two
// bundles.
//
// AND THE BUNDLE IS TESTED. tools/schema-check/verify.mjs applies this file to
// an empty database and runs the entire clinic suite against it. A bundle that
// is merely generated is a bundle nobody has proved installs.
//
// Re-run after ANY change under supabase/migrations:
//   node tools/build-clinic-setup.mjs

import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const migrationsDir = join(root, 'supabase', 'migrations');

const OPEN = '-- >>> shared-with-clinic';
const CLOSE = '-- <<< shared-with-clinic';

/** Pulls every marked region out of one migration, in file order. */
function sharedBlocks(sql) {
  const out = [];
  let from = 0;
  for (;;) {
    const start = sql.indexOf(OPEN, from);
    if (start === -1) break;
    const end = sql.indexOf(CLOSE, start);
    if (end === -1) throw new Error(`unclosed ${OPEN} marker`);
    out.push(sql.slice(start + OPEN.length, end).trim());
    from = end + CLOSE.length;
  }
  return out;
}

const files = readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort();

const shared = [];
const clinic = [];

for (const f of files) {
  const sql = readFileSync(join(migrationsDir, f), 'utf8');
  if (f.includes('_clinic_')) {
    clinic.push([f, sql]);
    continue;
  }
  for (const block of sharedBlocks(sql)) shared.push([f, block]);
}

// A bundle with no clinic in it would still be a valid SQL file, and would
// install a database that looks fine and does nothing. Fail loudly instead.
if (clinic.length === 0) throw new Error('no clinic migrations found — refusing to build');
if (shared.length === 0) {
  throw new Error(
    `no ${OPEN} regions found in the shop migrations — the clinic cannot stand up ` +
    'without profiles, fold_arabic and create_account'
  );
}

const parts = [
  `-- ============================================================================
-- العيادة — إعداد قاعدة بيانات مستقلة
--
-- GENERATED FILE — do not edit. Edit supabase/migrations/*.sql and re-run
--   node tools/build-clinic-setup.mjs
--
-- الملف ده لمشروع Supabase مخصص للعيادة لوحدها — مفيهوش أي حاجة من المحل.
--
-- HOW TO USE
--   1. اعمل مشروع Supabase جديد للعيادة بس
--   2. Supabase dashboard → SQL Editor → New query
--   3. الزق الملف ده كله → Run
--   4. Settings → API → Exposed schemas → ضيف \`clinic\`
--
-- Safe to run more than once: every statement is idempotent.
--
-- ⚠  WHAT IS IN HERE AND WHY
--
-- The first section is the small foundation the clinic sits on: the profiles
-- table that staff accounts hang off, the phone and Arabic-folding helpers the
-- search depends on, and the account-creation function with the three GoTrue
-- traps already solved in it.
--
-- Those are NOT copies. They are extracted from the very files the shop
-- installs, so the two deployments can never drift into folding an Arabic name
-- two different ways.
-- ============================================================================
`,
  '\n-- ############################################################################\n' +
  '-- ##  الأساس المشترك — مستخرج من ملفات المحل، مش منسوخ\n' +
  '-- ############################################################################\n',
];

let lastFile = null;
for (const [file, block] of shared) {
  if (file !== lastFile) {
    parts.push(`\n-- ## from ${file}\n`);
    lastFile = file;
  }
  parts.push(`\n${block}\n`);
}

parts.push(
  '\n-- ############################################################################\n' +
  '-- ##  العيادة\n' +
  '-- ############################################################################\n'
);

for (const [f, sql] of clinic) {
  parts.push(`\n-- ## ${f}\n`);
  parts.push(sql.trimEnd());
  parts.push('\n');
}

const out = join(root, 'supabase', 'SETUP-CLINIC-ONLY.sql');
writeFileSync(out, parts.join(''), 'utf8');

console.log(`wrote ${out}`);
console.log(`  ${shared.length} shared block(s) from ${new Set(shared.map((s) => s[0])).size} shop migration(s)`);
console.log(`  ${clinic.length} clinic migration(s)`);
