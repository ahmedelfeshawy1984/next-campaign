'use client';

// سلة عرض السعر — localStorage, wrapped so private browsing cannot crash it.
//
// The safeStore idea is ported from BALL STORE's assets/js/store.js (lines
// 12-21) and it earns its place for the same reason: Safari in private mode
// throws on localStorage.setItem, and a shop that white-screens for those
// visitors loses them silently.
//
// What is stored is the CONFIGURATION, not the price. Prices are recomputed
// from quote_product() every time the basket is rendered, so a basket left open
// across a price change shows today's number rather than a stale one — and
// create_order_request() recomputes again on the server regardless.

export interface BasketText {
  slot: number;
  content: string;
  font_key: string | null;
}

export interface BasketLine {
  /** Local id, so a line can be removed without ambiguity. */
  key: string;
  product_id: string;
  slug: string;
  name_ar: string;
  cover_url: string | null;
  qty: number;
  method_code: string | null;
  colors: number;
  position_ids: string[];
  option_item_ids: string[];
  texts: BasketText[];
  asset_paths: string[];
  notes?: string | null;
}

const KEY = 'nc_quote';
const LAST_ORDER_KEY = 'nc_last_order';

export interface LastOrder {
  id: string;
  code: string;
  phone: string;
  total: number;
  at: string;
}

/** localStorage that degrades to memory instead of throwing. */
const memory = new Map<string, string>();

function read(key: string): string | null {
  try {
    return window.localStorage.getItem(key);
  } catch {
    return memory.get(key) ?? null;
  }
}

function write(key: string, value: string): void {
  try {
    window.localStorage.setItem(key, value);
  } catch {
    memory.set(key, value);
  }
}

export function getBasket(): BasketLine[] {
  if (typeof window === 'undefined') return [];
  try {
    const raw = read(KEY);
    if (!raw) return [];
    const parsed: unknown = JSON.parse(raw);
    return Array.isArray(parsed) ? (parsed as BasketLine[]) : [];
  } catch {
    // A corrupt basket is not worth a broken page.
    return [];
  }
}

export function setBasket(lines: BasketLine[]): void {
  if (typeof window === 'undefined') return;
  write(KEY, JSON.stringify(lines));
  window.dispatchEvent(new CustomEvent('nc:basket'));
}

export function addLine(line: Omit<BasketLine, 'key'>): BasketLine[] {
  const key = `${line.product_id}-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
  const next = [...getBasket(), { ...line, key }];
  setBasket(next);
  return next;
}

export function removeLine(key: string): BasketLine[] {
  const next = getBasket().filter((l) => l.key !== key);
  setBasket(next);
  return next;
}

export function clearBasket(): void {
  setBasket([]);
}

export function basketCount(): number {
  return getBasket().length;
}

/**
 * The last order this device placed. Kept so /track can look it up without the
 * customer keeping a reference number, and so the confirmation page survives a
 * refresh. Reading it back still needs the phone — see order_status() in SQL.
 */
export function setLastOrder(order: LastOrder): void {
  if (typeof window === 'undefined') return;
  write(LAST_ORDER_KEY, JSON.stringify(order));
}

export function getLastOrder(): LastOrder | null {
  if (typeof window === 'undefined') return null;
  try {
    const raw = read(LAST_ORDER_KEY);
    return raw ? (JSON.parse(raw) as LastOrder) : null;
  } catch {
    return null;
  }
}
