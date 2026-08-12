// ترتيب نتايج البحث عن الدوا.
//
// AUTHORED AS .js ON PURPOSE — the same reason as phone.js and arabic.js:
// tools/schema-check/clinic.mjs imports this exact file and runs it against the
// REAL seeded catalogue pulled out of Postgres. That test is the only thing
// standing between "الدكتور بيكتب أول حرف والدوا بيطلع" as a design goal and as
// a fact.
//
// Pure on purpose too. The caller owns the array and the IndexedDB around it;
// this function just ranks, so it can be exercised without a browser.

import { foldArabic } from '../arabic.js';

/**
 * @typedef {object} DrugRow
 * @property {string} id
 * @property {string} trade_name
 * @property {string} [trade_name_ar]  the brand as an Arabic-typing doctor spells it
 * @property {string} name_key   folded server-side by public.fold_arabic()
 */

/**
 * Ranked matches for what the doctor has typed so far.
 *
 * The ranks, and why they are in this order:
 *
 *   0  the TRADE NAME starts with it.  "aug" → Augmentin. This is what someone
 *      reaching for a drug they already have in mind is doing, and it has to
 *      win outright.
 *   1  a WORD inside the entry starts with it. "بارا" → the paracetamol
 *      products, found through their generic name rather than their brand.
 *   2  it appears anywhere at all. The safety net for a half-remembered
 *      spelling, and last because it matches a lot.
 *
 * Within a rank, the drugs THIS doctor prescribes most come first. After a
 * week that is what makes the box feel like it is reading their mind, and it
 * costs one integer per row.
 *
 * @param {DrugRow[]} drugs
 * @param {Record<string, number>} usage  drug id → how often this doctor used it
 * @param {string} term
 * @param {number} [limit]
 * @returns {(DrugRow & { rank: number })[]}
 */
export function rankDrugs(drugs, usage, term, limit = 12) {
  const q = foldArabic(term).trim();

  if (q === '') {
    // An empty box shows habits rather than nothing: the doctor's usual drugs
    // are the likeliest next tap, and an empty dropdown teaches people the
    // feature is broken.
    return drugs
      .filter((d) => (usage[d.id] ?? 0) > 0)
      .sort((a, b) => (usage[b.id] ?? 0) - (usage[a.id] ?? 0))
      .slice(0, limit)
      .map((d) => ({ ...d, rank: 0 }));
  }

  const hits = [];
  for (const d of drugs) {
    const key = d.name_key ?? '';
    const at = key.indexOf(q);
    if (at === -1) continue;

    // BOTH spellings of the brand count as a rank-0 match. Checking only the
    // Latin one would rank Concor below every drug whose generic text happens
    // to contain "كونكور" — for a doctor typing Arabic, the brand they asked
    // for by name would not be first.
    let rank;
    if (
      foldArabic(d.trade_name).startsWith(q) ||
      (d.trade_name_ar ? foldArabic(d.trade_name_ar).startsWith(q) : false)
    ) rank = 0;
    else if (at === 0 || key[at - 1] === ' ') rank = 1;
    else rank = 2;

    hits.push({ ...d, rank });
  }

  hits.sort(
    (a, b) =>
      a.rank - b.rank ||
      (usage[b.id] ?? 0) - (usage[a.id] ?? 0) ||
      a.trade_name.localeCompare(b.trade_name, 'ar')
  );
  return hits.slice(0, limit);
}
