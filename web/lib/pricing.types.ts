import type { Numeric, PrintColorModel } from './types';

// The shapes quote_product() returns and computeQuote() consumes.
//
// TYPES ONLY. The arithmetic lives in pricing.js, in JavaScript, because
// tools/schema-check/verify.mjs imports it and compares it against SQL — see
// the header of that file. Splitting them this way keeps the nice syntax for
// the types (this file is erased at runtime and never imported by Node) and
// keeps the implementation importable by the harness.
//
// pricing.js references these with JSDoc `@typedef {import('./pricing.types')…}`,
// so the two halves stay type-checked as one.

export interface QuoteTier {
  min_qty: number;
  unit_price: Numeric;
}

export interface QuoteOptionItem {
  id: string;
  value: string;
  label_ar: string;
  hex: string | null;
  price_delta: Numeric;
  is_available: boolean;
  image_url: string | null;
}

export interface QuoteOptionGroup {
  id: string;
  code: string;
  label_ar: string;
  is_required: boolean;
  items: QuoteOptionItem[];
}

export interface QuoteMethod {
  code: string;
  name_ar: string;
  blurb_ar: string | null;
  color_model: PrintColorModel;
  uses_color_count: boolean;
  needs_vector: boolean;
  setup_fee: Numeric;
  setup_fee_per_color: boolean;
  setup_fee_waived_over_qty: number | null;
  unit_addon: Numeric;
  addon_per_color: Numeric;
  max_colors: number | null;
  method_min_qty: number | null;
  is_default: boolean;
}

export interface QuotePositionMethod {
  code: string;
  max_colors: number | null;
  area_w_mm: Numeric | null;
  area_h_mm: Numeric | null;
}

export interface QuotePosition {
  id: string;
  code: string;
  name_ar: string;
  area_w_mm: Numeric | null;
  area_h_mm: Numeric | null;
  preview_x: Numeric | null;
  preview_y: Numeric | null;
  preview_w: Numeric | null;
  preview_h: Numeric | null;
  preview_rotate: Numeric;
  is_default: boolean;
  methods: QuotePositionMethod[];
}

export interface QuoteFont {
  key: string;
  name_ar: string;
  css_family: string;
  script: 'arabic' | 'latin' | 'both';
  is_display: boolean;
}

export interface PriceBook {
  product_id: string;
  slug: string;
  name_ar: string;
  moq: number;
  max_positions: number;
  max_text_lines: number;
  allows_logo: boolean;
  allows_text: boolean;
  lead_days_min: number | null;
  lead_days_max: number | null;
  currency: string;
  vat_rate: Numeric;
  prices_include_vat: boolean;
  tiers: QuoteTier[];
  option_groups: QuoteOptionGroup[];
  methods: QuoteMethod[];
  positions: QuotePosition[];
  fonts: QuoteFont[];
}

export interface Selection {
  qty: number;
  methodCode: string | null;
  colors: number;
  positionIds: string[];
  optionItemIds: string[];
}

/** Stable markers, mirroring the codes price_quote() returns. */
export type QuoteError =
  | 'PRODUCT_NOT_FOUND'
  | 'QTY_INVALID'
  | 'QTY_BELOW_MOQ'
  | 'NO_PRICE_TIER'
  | 'OPTION_UNAVAILABLE'
  | 'OPTION_NOT_ON_PRODUCT'
  | 'METHOD_NOT_SUPPORTED'
  | 'TOO_MANY_COLORS'
  | 'QTY_BELOW_METHOD_MIN'
  | 'TOO_MANY_POSITIONS'
  | 'POSITION_METHOD_NOT_ALLOWED'
  | 'POSITION_NOT_ON_PRODUCT';

export interface Quote {
  ok: boolean;
  errors: QuoteError[];
  qty: number;
  colors: number;
  /** All amounts are INTEGER PIASTRES. Use toPounds() at the edge. */
  tierUnitPrice: number;
  optionsDelta: number;
  methodAddon: number;
  unitPrice: number;
  subtotal: number;
  setupTotal: number;
  preVat: number;
  vatAmount: number;
  total: number;
  currency: string;
}
