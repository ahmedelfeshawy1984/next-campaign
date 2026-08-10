// Egyptian mobile numbers, folded to one canonical spelling.
//
// AUTHORED AS .js ON PURPOSE. tools/schema-check/verify.mjs imports this exact
// file and asserts it agrees with public.normalize_phone() in SQL on all six
// spellings. A .ts copy would need a build step in the harness, and the moment
// the harness compiles its own copy it stops testing the one the site ships.
// JSDoc gives the app full type checking anyway (tsconfig: allowJs + checkJs).
//
// The canonical form is the local one — 01001234567 — not +20. It is what an
// Egyptian reads back to you over the phone, and it is what the owner types
// into the admin search box.

/**
 * Folds any spelling of an Egyptian number into `01XXXXXXXXX`.
 *
 * Handles Arabic-Indic ٠١٢ and Eastern-Arabic ۰۱۲ digits, the +20 and 0020
 * country prefixes, spaces, dashes and brackets, and a leading zero someone
 * dropped. Returns `''` for input with no digits at all.
 *
 * @param {string | null | undefined} raw
 * @returns {string}
 */
export function normalizePhone(raw) {
  if (raw == null) return '';

  let v = String(raw);
  v = v.replace(/[٠-٩]/g, (d) => String('٠١٢٣٤٥٦٧٨٩'.indexOf(d)));
  v = v.replace(/[۰-۹]/g, (d) => String('۰۱۲۳۴۵۶۷۸۹'.indexOf(d)));
  v = v.replace(/[^0-9]/g, '');

  if (v.startsWith('0020')) v = '0' + v.slice(4);
  if (v.startsWith('20') && v.length === 12) v = '0' + v.slice(2);
  if (v.length === 10 && v.startsWith('1')) v = '0' + v;

  return v;
}

/**
 * Is this a mobile number actually in service in Egypt? 010 / 011 / 012 / 015
 * are the only four prefixes; everything else is a landline or a typo.
 *
 * Client-side validation is a courtesy that saves a round trip. The gate is
 * `public.is_eg_mobile()` on the server — this function is not security.
 *
 * @param {string | null | undefined} raw
 * @returns {boolean}
 */
export function isEgMobile(raw) {
  return /^01[0125][0-9]{8}$/.test(normalizePhone(raw));
}

/**
 * `01001234567` → `0100 123 4567`. Display only — never store this.
 *
 * @param {string | null | undefined} raw
 * @returns {string}
 */
export function prettyPhone(raw) {
  const v = normalizePhone(raw);
  if (!isEgMobile(v)) return String(raw ?? '');
  return `${v.slice(0, 4)} ${v.slice(4, 7)} ${v.slice(7)}`;
}
