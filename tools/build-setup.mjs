// Concatenates every migration plus the seed into supabase/SETUP-ALL-IN-ONE.sql.
//
// That single file is the install path: open the Supabase SQL editor, paste,
// run. The person who owns this system has no terminal and no Supabase CLI, so
// "apply the migrations" has to mean one paste, not twelve in order.
//
// Re-run after ANY change under supabase/migrations:
//   G:\dev-tools\node\node.exe tools/build-setup.mjs

import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const migrationsDir = join(root, 'supabase', 'migrations');

const files = readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort();
if (files.length === 0) throw new Error('no migrations found');

// The RLS file revokes execute on every function from anon. Anything sorting
// before it creates a function whose grant is immediately taken away — and
// because an already-installed database never re-runs the RLS file, the fault
// only shows up on a fresh install, months later, in front of whoever is
// setting the system up for the first time. Catch it at build time instead.
const rlsIndex = files.findIndex((f) => f.includes('_rls'));
if (rlsIndex === -1) throw new Error('no _rls migration found — refusing to build');
const afterRls = files.slice(rlsIndex + 1);
if (afterRls.length === 0) {
  console.warn('note: nothing sorts after the RLS migration yet');
}

const parts = [
  `-- ============================================================================
-- نكست كامباين — Next Campaign · complete database setup
--
-- GENERATED FILE — do not edit. Edit supabase/migrations/*.sql and re-run
--   node tools/build-setup.mjs
--
-- HOW TO USE
--   1. Supabase dashboard → SQL Editor → New query
--   2. Paste this whole file
--   3. Run
--
-- Safe to run more than once: every statement is idempotent.
-- ============================================================================
`,
];

for (const f of files) {
  parts.push(`\n-- ## ${f}\n`);
  parts.push(readFileSync(join(migrationsDir, f), 'utf8').trimEnd());
  parts.push('\n');
}

parts.push('\n-- ## seed.sql\n');
parts.push(readFileSync(join(root, 'supabase', 'seed.sql'), 'utf8').trimEnd());
parts.push('\n');

const out = join(root, 'supabase', 'SETUP-ALL-IN-ONE.sql');
writeFileSync(out, parts.join(''), 'utf8');
console.log(`wrote ${out} from ${files.length} migrations + seed`);
console.log(`  ${afterRls.length} migration(s) sort after _rls and must carry their own grants`);
