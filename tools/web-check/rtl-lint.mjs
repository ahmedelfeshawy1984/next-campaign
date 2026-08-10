// Refuses physical CSS properties.
//
// The document is RTL and the admin panel will one day be LTR English. A
// `margin-left` is correct in exactly one of those and wrong in the other, and
// the wrongness is invisible to whoever wrote it because they only ever look at
// one direction. Logical properties are correct in both.
//
// This turns a convention that would otherwise live in a code review into a
// check that fails the build.
//
//   G:\dev-tools\node\node.exe tools/web-check/rtl-lint.mjs

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, dirname, relative, extname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '../..');
const webDir = join(root, 'web');

const BANNED = [
  // property: suggestion
  [/(^|[^-\w])margin-left\s*:/, 'margin-inline-start'],
  [/(^|[^-\w])margin-right\s*:/, 'margin-inline-end'],
  [/(^|[^-\w])padding-left\s*:/, 'padding-inline-start'],
  [/(^|[^-\w])padding-right\s*:/, 'padding-inline-end'],
  [/(^|[^-\w])border-left\b/, 'border-inline-start'],
  [/(^|[^-\w])border-right\b/, 'border-inline-end'],
  [/(^|[^-\w])text-align\s*:\s*(left|right)\b/, 'text-align: start / end'],
  [/(^|[^-\w])float\s*:\s*(left|right)\b/, 'float: inline-start / inline-end'],
  // Bare left:/right:/top-level positioning. `inset-inline-*` and
  // `inset-block-*` say which edge they mean in a direction-aware way.
  [/(^|[^-\w])(left|right)\s*:\s*[-\d]/, 'inset-inline-start / inset-inline-end'],
  // The JSX equivalents.
  [/\bmarginLeft\b/, 'marginInlineStart'],
  [/\bmarginRight\b/, 'marginInlineEnd'],
  [/\bpaddingLeft\b/, 'paddingInlineStart'],
  [/\bpaddingRight\b/, 'paddingInlineEnd'],
  [/\bborderLeft\b/, 'borderInlineStart'],
  [/\bborderRight\b/, 'borderInlineEnd'],
];

// Genuinely direction-independent uses. `dir="ltr"` on a phone number is the
// point, not a violation; a transform or a gradient has no writing direction.
const ALLOW_LINE = /rtl-ok|dir=|linear-gradient|radial-gradient|translate|rotate|scroll-behavior/;

const EXTS = new Set(['.css', '.tsx', '.ts', '.jsx', '.js']);
const SKIP_DIRS = new Set(['node_modules', '.next', 'out', '.git']);

/** @param {string} dir @returns {string[]} */
function walk(dir) {
  /** @type {string[]} */
  const out = [];
  for (const name of readdirSync(dir)) {
    if (SKIP_DIRS.has(name)) continue;
    const full = join(dir, name);
    if (statSync(full).isDirectory()) out.push(...walk(full));
    else if (EXTS.has(extname(name))) out.push(full);
  }
  return out;
}

let failures = 0;
let scanned = 0;

for (const file of walk(webDir)) {
  scanned++;
  const lines = readFileSync(file, 'utf8').split(/\r?\n/);
  lines.forEach((line, i) => {
    if (ALLOW_LINE.test(line)) return;
    for (const [re, better] of BANNED) {
      if (re.test(line)) {
        failures++;
        console.log(
          `FAIL  ${relative(root, file)}:${i + 1}  ${line.trim().slice(0, 80)}\n      use ${better}`
        );
        break;
      }
    }
  });
}

console.log(
  failures === 0
    ? `PASS  rtl-lint — ${scanned} files, no physical properties`
    : `\n${failures} physical propert${failures === 1 ? 'y' : 'ies'} found in ${scanned} files`
);
process.exit(failures ? 1 : 0);
