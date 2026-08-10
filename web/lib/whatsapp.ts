import { normalizePhone } from './phone';

// Ported from BALL STORE's assets/js/store.js (buildOrderMessage / whatsappLink),
// which is the part of that project worth keeping: a plain-text message a human
// can read in the chat, and a wa.me link rather than the whatsapp:// scheme —
// wa.me works on desktop, in-app browsers and on a phone with no WhatsApp
// installed, where the scheme just fails silently.
//
// buildOrderMessage below is the direct descendant of that project's
// `buildOrderMessage` — numbered lines, then the totals, then the delivery
// details, in plain text a human can read in the chat without scrolling
// sideways.

/**
 * A wa.me link, or null when no number is configured.
 *
 * Returns null rather than a broken link on purpose — the footer and the
 * product page both check, and a button that opens wa.me/undefined is worse
 * than no button.
 */
export function whatsappLink(
  phone: string | null | undefined,
  message?: string
): string | null {
  const local = normalizePhone(phone);
  if (!local || local.length < 10) return null;

  // wa.me wants the international form with no plus and no leading zero.
  const intl = local.startsWith('0') ? `20${local.slice(1)}` : local;
  const text = message ? `?text=${encodeURIComponent(message)}` : '';
  return `https://wa.me/${intl}${text}`;
}

export interface OrderMessageLine {
  name_ar: string;
  qty: number;
  method_name_ar?: string | null;
  colors?: number | null;
  positions?: string[];
  options?: string[];
  texts?: string[];
  assets?: number;
}

export interface OrderMessageInput {
  code: string;
  contactName: string;
  companyName?: string | null;
  phone: string;
  governorate?: string | null;
  neededBy?: string | null;
  lines: OrderMessageLine[];
  /** Display strings, already formatted with the currency. */
  subtotal: string;
  setup: string;
  vat: string | null;
  total: string;
  note?: string | null;
}

/**
 * The message the customer sends us.
 *
 * It is a SUMMARY, not the order: the order is already in the database with its
 * artwork by the time this opens. That is the whole difference from the static
 * sibling site, where the WhatsApp text WAS the record and the logo was an
 * attachment somebody had to find again three weeks later.
 *
 * The code goes first, on its own line, because it is what ties the chat to the
 * row.
 */
export function buildOrderMessage(o: OrderMessageInput): string {
  const L: string[] = [];

  L.push(`طلب جديد رقم ${o.code}`);
  L.push('');

  o.lines.forEach((line, i) => {
    L.push(`${i + 1}. ${line.name_ar} — ${line.qty} قطعة`);
    const bits: string[] = [];
    if (line.method_name_ar) {
      bits.push(line.colors && line.colors > 1
        ? `${line.method_name_ar} (${line.colors} ألوان)`
        : line.method_name_ar);
    }
    if (line.positions?.length) bits.push(line.positions.join(' + '));
    if (line.options?.length) bits.push(line.options.join('، '));
    if (bits.length) L.push(`   ${bits.join(' · ')}`);
    if (line.texts?.length) L.push(`   النص: ${line.texts.join(' / ')}`);
    if (line.assets) L.push(`   مرفق ${line.assets} ملف تصميم`);
  });

  L.push('');
  L.push(`الإجمالي قبل الضريبة: ${o.subtotal}`);
  if (o.setup) L.push(`رسوم التجهيز: ${o.setup}`);
  if (o.vat) L.push(`الضريبة: ${o.vat}`);
  L.push(`*الإجمالي: ${o.total}*`);
  L.push('');

  L.push(`الاسم: ${o.contactName}`);
  if (o.companyName) L.push(`الشركة: ${o.companyName}`);
  L.push(`الموبايل: ${o.phone}`);
  if (o.governorate) L.push(`المحافظة: ${o.governorate}`);
  if (o.neededBy) L.push(`مطلوب قبل: ${o.neededBy}`);
  if (o.note) L.push(`ملاحظات: ${o.note}`);

  L.push('');
  L.push('الملفات مرفوعة على الموقع مع الطلب.');

  return L.join('\n');
}
