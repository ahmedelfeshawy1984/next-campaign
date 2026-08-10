// Arabic text folding for search.
//
// AUTHORED AS .js ON PURPOSE — same reason as phone.js: the schema harness
// imports this exact file and asserts it agrees with `public.fold_arabic()`
// and with the stored `products.search_key` generated column. Three
// implementations of one rule are only acceptable when a test proves they are
// one rule.

const FROM = 'أإآةىًٌٍَُِّْ';
const TO = 'اااهي';

/**
 * Folds the differences people do not type consistently: أ إ آ → ا, ة → ه,
 * ى → ي, and every tashkeel mark dropped.
 *
 * Mirrors `translate(lower(x), 'أإآةىًٌٍَُِّْ', 'اااهي')` in Postgres. Note the
 * replacement string is SHORTER than the source: translate() DELETES any source
 * character with no counterpart, so the five letters map and the eight tashkeel
 * marks vanish. Replacing them with spaces instead would split "مُحرِّك" into
 * three unmatchable words.
 *
 * @param {string | null | undefined} raw
 * @returns {string}
 */
export function foldArabic(raw) {
  if (raw == null) return '';
  let out = '';
  for (const ch of String(raw).toLowerCase()) {
    const i = FROM.indexOf(ch);
    if (i === -1) out += ch;
    else if (i < TO.length) out += TO[i];
    // i >= TO.length → a tashkeel mark, dropped entirely
  }
  return out;
}

/**
 * Latin digits inside Arabic text, always.
 *
 * `٢٥٠` reads as a foreign object in a price and copies badly into WhatsApp and
 * into a spreadsheet. Prices, quantities, phone numbers and order codes stay
 * Western — the same decision as the sibling projects' `Fmt.price`.
 *
 * @param {string | null | undefined} raw
 * @returns {string}
 */
export function toLatinDigits(raw) {
  if (raw == null) return '';
  return String(raw)
    .replace(/[٠-٩]/g, (d) => String('٠١٢٣٤٥٦٧٨٩'.indexOf(d)))
    .replace(/[۰-۹]/g, (d) => String('۰۱۲۳۴۵۶۷۸۹'.indexOf(d)));
}
