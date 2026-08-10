import { toPiastres } from './money.js';

// THE EVALUATOR — not a second set of rules.
//
// Every rule this file applies (which rung, which fee, which waiver, which
// ceiling) is DATA produced by quote_product() in
// supabase/migrations/20260810100008_quote.sql. This file only does arithmetic,
// so the total can move on every keystroke without a round trip.
//
// price_quote() in SQL is the AUTHORITY: create_order_request() recomputes
// there and stores its own numbers. tools/schema-check/verify.mjs fuzzes 200
// random selections through both and asserts they agree TO THE PIASTRE. If you
// change the arithmetic here, change it there in the same commit — the harness
// will not let you do otherwise.
//
// AUTHORED AS .js for that reason: the harness imports this exact file. Types
// live in pricing.types.ts and are pulled in below as JSDoc typedefs, so this
// is checked as strictly as TypeScript would check it.
//
// EVERYTHING IS INTEGER PIASTRES. Floating-point pounds drift by a piastre on
// exactly the order the customer screenshots, and a parity test between two
// implementations means nothing if either side can round differently.

/**
 * @typedef {import('./pricing.types').PriceBook} PriceBook
 * @typedef {import('./pricing.types').Selection} Selection
 * @typedef {import('./pricing.types').Quote} Quote
 * @typedef {import('./pricing.types').QuoteError} QuoteError
 * @typedef {import('./pricing.types').QuoteTier} QuoteTier
 * @typedef {import('./pricing.types').QuoteMethod} QuoteMethod
 * @typedef {import('./pricing.types').QuotePosition} QuotePosition
 * @typedef {import('./pricing.types').QuoteOptionItem} QuoteOptionItem
 */

/**
 * The greatest rung at or below the quantity. Null when there is none — which
 * is a real state, not a zero: a quantity below the cheapest rung has no price,
 * and pricing it as free is worse than saying so.
 *
 * @param {QuoteTier[]} tiers
 * @param {number} qty
 * @returns {QuoteTier | null}
 */
export function tierFor(tiers, qty) {
  /** @type {QuoteTier | null} */
  let best = null;
  for (const t of tiers) {
    if (t.min_qty <= qty && (!best || t.min_qty > best.min_qty)) best = t;
  }
  return best;
}

/**
 * The next rung up, for "take 100 and save 12%". Null at the top of the ladder.
 *
 * @param {QuoteTier[]} tiers
 * @param {number} qty
 * @returns {QuoteTier | null}
 */
export function nextTier(tiers, qty) {
  /** @type {QuoteTier | null} */
  let next = null;
  for (const t of tiers) {
    if (t.min_qty > qty && (!next || t.min_qty < next.min_qty)) next = t;
  }
  return next;
}

/**
 * @param {PriceBook} book
 * @param {string | null} code
 * @returns {QuoteMethod | null}
 */
export function methodByCode(book, code) {
  if (!code) return null;
  return book.methods.find((m) => m.code === code) ?? null;
}

/**
 * The resolved colour ceiling, honouring the position → product → method
 * override chain that quote_product() already flattened.
 *
 * @param {PriceBook} book
 * @param {string} methodCode
 * @param {string} [positionId]
 * @returns {number | null}
 */
export function maxColorsAt(book, methodCode, positionId) {
  if (positionId) {
    const pos = book.positions.find((p) => p.id === positionId);
    const pm = pos?.methods.find((m) => m.code === methodCode);
    if (pm && pm.max_colors != null) return pm.max_colors;
  }
  return methodByCode(book, methodCode)?.max_colors ?? null;
}

/**
 * @param {QuotePosition} pos
 * @param {string} methodCode
 * @returns {boolean}
 */
export function positionAllowsMethod(pos, methodCode) {
  return pos.methods.some((m) => m.code === methodCode);
}

/**
 * @param {number} qty
 * @param {number} colors
 * @param {string} currency
 * @param {QuoteError[]} errors
 * @returns {Quote}
 */
function emptyQuote(qty, colors, currency, errors) {
  return {
    ok: false,
    errors,
    qty,
    colors,
    tierUnitPrice: 0,
    optionsDelta: 0,
    methodAddon: 0,
    unitPrice: 0,
    subtotal: 0,
    setupTotal: 0,
    preVat: 0,
    vatAmount: 0,
    total: 0,
    currency,
  };
}

/**
 * The whole quote. Mirrors price_quote() statement for statement.
 *
 * @param {PriceBook} book
 * @param {Selection} sel
 * @returns {Quote}
 */
export function computeQuote(book, sel) {
  /** @type {QuoteError[]} */
  const errors = [];
  const currency = book.currency;
  const vatRate = Number(book.vat_rate) || 0;

  if (!Number.isFinite(sel.qty) || sel.qty < 1) {
    return emptyQuote(sel.qty, sel.colors, currency, ['QTY_INVALID']);
  }

  const qty = Math.floor(sel.qty);
  if (qty < book.moq) errors.push('QTY_BELOW_MOQ');

  // ---- the rung -----------------------------------------------------------
  const tier = tierFor(book.tiers, qty);
  if (!tier) errors.push('NO_PRICE_TIER');
  const tierUnitPrice = tier ? toPiastres(tier.unit_price) : 0;

  // ---- options ------------------------------------------------------------
  /** @type {Map<string, QuoteOptionItem>} */
  const allItems = new Map();
  for (const g of book.option_groups) for (const i of g.items) allItems.set(i.id, i);

  let optionsDelta = 0;
  let matched = 0;
  for (const id of sel.optionItemIds) {
    const item = allItems.get(id);
    if (!item) continue;
    matched++;
    if (!item.is_available && !errors.includes('OPTION_UNAVAILABLE')) {
      errors.push('OPTION_UNAVAILABLE');
    }
    optionsDelta += toPiastres(item.price_delta);
  }
  // An option id belonging to a different product must not silently price as
  // zero: that is a stale configuration, and quoting it as free is how a
  // customer ends up promised something we never agreed to make.
  if (matched !== sel.optionItemIds.length) errors.push('OPTION_NOT_ON_PRODUCT');

  // ---- the method ---------------------------------------------------------
  let colors = Math.max(Math.floor(sel.colors) || 1, 1);
  let methodAddon = 0;
  const method = methodByCode(book, sel.methodCode);

  if (sel.methodCode && !method) {
    errors.push('METHOD_NOT_SUPPORTED');
  } else if (method) {
    // Laser engraves the material — there is no colour to charge for, and the
    // configurator does not offer one.
    if (!method.uses_color_count) colors = 1;

    if (method.uses_color_count && method.max_colors != null && colors > method.max_colors) {
      errors.push('TOO_MANY_COLORS');
      colors = method.max_colors;
    }
    if (method.method_min_qty != null && qty < method.method_min_qty) {
      errors.push('QTY_BELOW_METHOD_MIN');
    }

    methodAddon =
      toPiastres(method.unit_addon) +
      (method.uses_color_count ? (colors - 1) * toPiastres(method.addon_per_color) : 0);
  }

  // ---- positions and their setup fees -------------------------------------
  if (sel.positionIds.length > book.max_positions) errors.push('TOO_MANY_POSITIONS');

  let setupTotal = 0;
  if (method) {
    let posMatched = 0;
    for (const id of sel.positionIds) {
      const pos = book.positions.find((p) => p.id === id);
      if (!pos) continue;
      posMatched++;

      if (
        !positionAllowsMethod(pos, method.code) &&
        !errors.includes('POSITION_METHOD_NOT_ALLOWED')
      ) {
        errors.push('POSITION_METHOD_NOT_ALLOWED');
      }

      // >= not >. A customer ordering exactly the threshold expects the free
      // cliché, and arguing about it costs more than it saves.
      const waived =
        method.setup_fee_waived_over_qty != null && qty >= method.setup_fee_waived_over_qty;
      if (!waived) {
        setupTotal += toPiastres(method.setup_fee) * (method.setup_fee_per_color ? colors : 1);
      }
    }
    if (posMatched !== sel.positionIds.length) errors.push('POSITION_NOT_ON_PRODUCT');
  }

  // ---- the total ----------------------------------------------------------
  const unitPrice = tierUnitPrice + optionsDelta + methodAddon;
  const subtotal = unitPrice * qty;
  const preVat = subtotal + setupTotal;

  // Basis points, so the multiply happens in integers and the .5 boundary lands
  // where Postgres `round(numeric, 2)` puts it.
  const vatBp = Math.round(vatRate * 10000);
  const vatAmount = book.prices_include_vat ? 0 : Math.round((preVat * vatBp) / 10000);

  return {
    ok: errors.length === 0,
    errors,
    qty,
    colors,
    tierUnitPrice,
    optionsDelta,
    methodAddon,
    unitPrice,
    subtotal,
    setupTotal,
    preVat,
    vatAmount,
    total: preVat + vatAmount,
    currency,
  };
}

/**
 * What the customer saves per piece by climbing to the next rung — the line
 * that turns a browser into an order.
 *
 * @param {PriceBook} book
 * @param {Selection} sel
 * @returns {{ atQty: number, percent: number } | null}
 */
export function nextRungSaving(book, sel) {
  const current = tierFor(book.tiers, sel.qty);
  const next = nextTier(book.tiers, sel.qty);
  if (!current || !next) return null;

  const now = toPiastres(current.unit_price);
  const then = toPiastres(next.unit_price);
  if (now <= 0 || then >= now) return null;

  const percent = Math.round(((now - then) / now) * 100);
  return percent >= 1 ? { atQty: next.min_qty, percent } : null;
}
