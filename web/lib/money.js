// Money.
//
// AUTHORED AS .js — the house rule is: anything tools/schema-check/verify.mjs
// has to import and compare against SQL is written in JavaScript with JSDoc
// types, never TypeScript. A .ts copy would need a build step in the harness,
// and the moment the harness compiles its own copy it stops testing the one the
// site ships. `checkJs` in tsconfig means these are type-checked exactly as
// strictly as a .ts file. Same reason as phone.js and arabic.js.
//
// EGP is carried as integer PIASTRES everywhere arithmetic happens, and turned
// back into a decimal only for display. Floating-point pounds drift by a
// piastre on exactly the order the customer screenshots, and the parity check
// between price_quote() in SQL and computeQuote() in JS compares piastres — a
// comparison that means nothing if either side can round differently.
//
// Digits stay Latin inside Arabic: '250 ج.م', never '٢٥٠ ج.م'. A price in
// Arabic-Indic digits copies badly into WhatsApp, into a spreadsheet and into a
// purchase order.

/**
 * Pounds (a number, or the numeric string PostgREST may hand back) → integer
 * piastres.
 *
 * @param {number | string | null | undefined} pounds
 * @returns {number}
 */
export function toPiastres(pounds) {
  if (pounds == null) return 0;
  const n = Number(pounds);
  return Number.isFinite(n) ? Math.round(n * 100) : 0;
}

/**
 * Integer piastres → pounds, for display only.
 *
 * @param {number} piastres
 * @returns {number}
 */
export function toPounds(piastres) {
  return piastres / 100;
}

/**
 * `1850` → `1,850` · `52.5` → `52.50`
 *
 * Whole pounds lose the decimals — a catalogue full of `.00` reads as a
 * spreadsheet export rather than a price list.
 *
 * @param {number | string | null | undefined} pounds
 * @returns {string}
 */
export function formatAmount(pounds) {
  if (pounds == null) return '—';
  const n = Number(pounds);
  if (!Number.isFinite(n)) return '—';
  const whole = Math.round(n * 100) % 100 === 0;
  return n.toLocaleString('en-US', {
    minimumFractionDigits: whole ? 0 : 2,
    maximumFractionDigits: 2,
  });
}

/**
 * `1850` → `1,850 ج.م`
 *
 * @param {number | string | null | undefined} pounds
 * @param {string} [currency]
 * @returns {string}
 */
export function formatPrice(pounds, currency = 'ج.م') {
  const amount = formatAmount(pounds);
  return amount === '—' ? amount : `${amount} ${currency}`;
}

/**
 * Piastres straight to a display string, so a caller holding the integer form
 * never has to remember to divide.
 *
 * @param {number} piastres
 * @param {string} [currency]
 * @returns {string}
 */
export function formatPiastres(piastres, currency = 'ج.م') {
  return formatPrice(toPounds(piastres), currency);
}

/**
 * Quantities are Latin digits too, and grouped over a thousand.
 *
 * @param {number | string | null | undefined} n
 * @returns {string}
 */
export function formatQty(n) {
  if (n == null) return '—';
  return Number(n).toLocaleString('en-US');
}

/**
 * How much cheaper this rung is than the baseline, as a whole percent.
 * Null when there is nothing worth advertising.
 *
 * @param {number | string | null | undefined} base
 * @param {number | string | null | undefined} price
 * @returns {number | null}
 */
export function savingPercent(base, price) {
  const b = Number(base);
  const p = Number(price);
  if (!Number.isFinite(b) || !Number.isFinite(p) || b <= 0 || p >= b) return null;
  const pct = Math.round(((b - p) / b) * 100);
  return pct >= 1 ? pct : null;
}
