// Turns preview mode on and off by swapping the data layer on disk.
//
// WHY A FILE SWAP AND NOT A BUNDLER ALIAS
//
// The obvious approach — aliasing '@/lib/queries' to the preview module in
// next.config — does not work: Turbopack (which `next dev` uses in 15.5) and
// webpack resolve the tsconfig `@/*` paths through their own plugin, which wins
// over resolve.alias. A config that silently does nothing is worse than no
// config, so the alias was removed and this took its place.
//
// The runtime alternative — a `process.env.PREVIEW` branch inside queries.ts —
// was rejected for a different reason: it would ship the 180 kB fixture dump
// and a fixture code path in the production bundle, where a misconfigured env
// var could serve stale seed data to a real customer. A file that is only
// swapped on a developer's machine cannot do that.
//
//   node tools/preview/toggle.mjs on     # catalogue from web/preview-data.json
//   node tools/preview/toggle.mjs off    # catalogue from Supabase (the default)
//   node tools/preview/toggle.mjs        # say which mode we are in

import { existsSync, renameSync, copyFileSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '../..');
const lib = join(root, 'web', 'lib');

const ACTIVE = join(lib, 'queries.ts');          // what the pages import
const LIVE = join(lib, 'queries.live.ts');       // the real one, parked while previewing
const PREVIEW = join(lib, 'queries.preview.ts'); // the fixture reader
const DUMP = join(root, 'web', 'preview-data.json');
const ENV_LOCAL = join(root, 'web', '.env.local');
const ENV_PREVIEW = join(root, 'web', '.env.preview');

const isOn = () => existsSync(LIVE);

function state() {
  if (isOn()) {
    const rows = existsSync(DUMP)
      ? JSON.parse(readFileSync(DUMP, 'utf8')).products?.length ?? 0
      : 0;
    console.log(`preview: ON — the catalogue is ${rows} products from web/preview-data.json`);
    console.log('         run `npm run preview:off` before committing or deploying');
  } else {
    console.log('preview: OFF — the catalogue comes from Supabase');
  }
}

const arg = process.argv[2];

if (!arg) {
  state();
} else if (arg === 'on') {
  if (isOn()) {
    state();
  } else {
    if (!existsSync(DUMP)) {
      console.error('no web/preview-data.json — run `npm run preview:dump` first');
      process.exit(1);
    }
    if (!existsSync(PREVIEW)) {
      console.error('no web/lib/queries.preview.ts');
      process.exit(1);
    }
    renameSync(ACTIVE, LIVE);
    copyFileSync(PREVIEW, ACTIVE);
    state();

    // Swapping the data layer is not enough on its own: app/layout.tsx checks
    // isConfigured and renders SetupRequired when the Supabase env vars are
    // missing, so preview mode without .env.local shows the setup screen and
    // looks like the swap failed. It has not; the catalogue is sitting behind a
    // guard nobody satisfied.
    //
    // Creating the file is safe because it only happens when there ISN'T one —
    // a real .env.local is never touched, and the placeholder values reach no
    // server.
    if (!existsSync(ENV_LOCAL) && existsSync(ENV_PREVIEW)) {
      copyFileSync(ENV_PREVIEW, ENV_LOCAL);
      console.log('         (وعملت web/.env.local بقيم وهمية عشان الموقع يفتح)');
    }
  }
} else if (arg === 'off') {
  if (!isOn()) {
    state();
  } else {
    // queries.ts is a COPY of the preview file while preview is on, so
    // overwriting it loses nothing. queries.live.ts is the only original.
    renameSync(LIVE, ACTIVE);
    state();
  }
} else {
  console.error(`unknown argument "${arg}" — expected on, off, or nothing`);
  process.exit(1);
}
