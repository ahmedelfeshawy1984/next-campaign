'use client';

import { browserSupabase } from './supabase-browser';
import type { PriceBook } from './pricing.types';
import type { BasketLine } from './basket';

// The three calls a customer can make, all through security-definer RPCs.
//
// There is no INSERT anywhere in this file, and there cannot be: the order
// tables carry no anon grant at all. Rate limiting, price recomputation and the
// artwork-ownership check all live inside create_order_request(), because the
// anon key ships in the bundle and anything enforced here is enforced nowhere.

export interface OrderCustomer {
  customer_kind: 'company' | 'individual';
  contact_name: string;
  contact_phone: string;
  contact_email?: string | null;
  company_name?: string | null;
  tax_id?: string | null;
  governorate?: string | null;
  area?: string | null;
  address?: string | null;
  needed_by?: string | null;
  ip_confirmed: boolean;
  portfolio_consent: boolean;
  note?: string | null;
}

export interface OrderResult {
  id: string;
  code: string;
  total: number;
  subtotal: number;
  setup_total: number;
  vat_amount: number;
}

/** Stable server markers → the sentence to show. */
const ORDER_ERRORS: Record<string, string> = {
  NAME_REQUIRED: 'اكتب اسمك من فضلك.',
  PHONE_INVALID: 'رقم الموبايل مش صحيح — لازم يبدأ بـ 010 أو 011 أو 012 أو 015.',
  IP_NOT_CONFIRMED: 'لازم تأكد إن لك حق استخدام الشعار قبل الإرسال.',
  NO_LINES: 'السلة فاضية.',
  RATE_LIMITED: 'بعتّ طلبات كتير في وقت قصير. كلمنا على واتساب وهنكمل معاك.',
  PRODUCT_NOT_FOUND: 'في منتج في السلة اتشال من الموقع — امسحه وجرّب تاني.',
  LINE_INVALID: 'في سطر اختياراته اتغيّرت. حدّث الصفحة وراجع الكمية والطباعة.',
  ASSET_NOT_YOURS: 'في ملف مش تبع الجلسة دي. ارفعه تاني من فضلك.',
  ASSET_NOT_REGISTERED: 'في ملف ما اتسجّلش صح. ارفعه تاني من فضلك.',
  NOT_SIGNED_IN: 'الجلسة انتهت. حدّث الصفحة وارفع الملف تاني.',
};

export function orderErrorMessage(raw: string): string {
  for (const [marker, message] of Object.entries(ORDER_ERRORS)) {
    if (raw.includes(marker)) return message;
  }
  return 'حصلت مشكلة وإحنا بنسجّل الطلب. جرّب تاني، ولو فضلت كلمنا على واتساب.';
}

export async function submitOrder(
  customer: OrderCustomer,
  lines: BasketLine[],
  clientTotalPounds: number
): Promise<OrderResult> {
  const payload = {
    ...customer,
    source: 'quote',
    client_total: clientTotalPounds,
    lines: lines.map((l) => ({
      product_id: l.product_id,
      qty: l.qty,
      method_code: l.method_code,
      colors: l.colors,
      position_ids: l.position_ids,
      option_item_ids: l.option_item_ids,
      texts: l.texts.filter((t) => t.content.trim() !== ''),
      asset_paths: l.asset_paths,
      notes: l.notes ?? null,
    })),
  };

  const { data, error } = await browserSupabase().rpc('create_order_request', {
    p_payload: payload,
  });
  if (error) throw new Error(orderErrorMessage(error.message));
  return data as OrderResult;
}

export async function fetchPriceBook(productId: string): Promise<PriceBook | null> {
  const { data, error } = await browserSupabase().rpc('quote_product', {
    p_product: productId,
  });
  if (error) throw error;
  return (data as PriceBook) ?? null;
}

export interface TrackedOrder {
  code: string;
  status: string;
  total: number;
  created_at: string;
  needed_by: string | null;
  deposit_received: boolean;
  lines: {
    product_name_ar: string;
    qty: number;
    method_name_ar: string | null;
    line_total: number;
  }[];
}

/**
 * Reading an order back needs BOTH the id and the phone.
 *
 * Either alone is a way into somebody else's order: ids leak through browser
 * history and shared links, and phone numbers are guessable.
 */
export async function trackOrder(id: string, phone: string): Promise<TrackedOrder | null> {
  const { data, error } = await browserSupabase().rpc('order_status', {
    p_id: id,
    p_phone: phone,
  });
  if (error) throw error;
  return (data as TrackedOrder) ?? null;
}

/**
 * Records that the customer reached the WhatsApp handoff.
 *
 * Not proof they sent it — nothing can be — but it separates "filled the form
 * and vanished" from "filled the form and opened the chat", and those are
 * different follow-up calls.
 */
export async function markWhatsappSent(id: string, phone: string): Promise<void> {
  try {
    await browserSupabase().rpc('mark_whatsapp_sent', { p_id: id, p_phone: phone });
  } catch {
    // Deliberately swallowed: a failure here must never stand between the
    // customer and WhatsApp, which is the entire point of the button.
  }
}

export const ORDER_STATUS_AR: Record<string, string> = {
  new: 'وصلنا الطلب',
  contacted: 'اتصلنا بيك',
  quoted: 'بعتنا عرض السعر',
  artwork_review: 'بنراجع التصميم',
  artwork_approved: 'التصميم اتعتمد',
  in_production: 'تحت التنفيذ',
  ready: 'جاهز للاستلام',
  delivered: 'اتسلّم',
  cancelled: 'ملغي',
};
