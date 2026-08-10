'use client';

import { browserSupabase } from './supabase-browser';

// One fetch, used by both the order screen and the printed job sheet.
//
// They show the same facts to two different readers — the owner on a phone and
// the workshop on paper — and the day they read from different queries is the
// day the sheet says something the screen does not.

export interface AdminOrderLine {
  id: string;
  line_no: number;
  product_id: string | null;
  product_name_ar: string;
  product_slug: string | null;
  category_name_ar: string | null;
  qty: number;
  moq_at_request: number | null;
  method_code: string | null;
  method_name_ar: string | null;
  colors_count: number | null;
  setup_fee_at_request: number;
  unit_price_at_request: number;
  options_delta: number;
  method_addon: number;
  line_subtotal: number;
  line_total: number;
  gift_message: string | null;
  notes: string | null;
  order_line_positions: {
    position_name_ar: string;
    area_w_mm: number | null;
    area_h_mm: number | null;
  }[];
  order_line_options: {
    group_label_ar: string;
    item_label_ar: string;
    hex: string | null;
  }[];
  order_line_texts: {
    slot: number;
    content: string;
    font_name_ar: string | null;
    color_hex: string | null;
    pantone_code: string | null;
  }[];
  order_line_assets: {
    id: string;
    storage_path: string;
    original_name: string | null;
    bytes: number | null;
    px_width: number | null;
    px_height: number | null;
    dpi_at_position: number | null;
  }[];
}

export interface AdminOrder {
  id: string;
  code: string;
  customer_kind: string;
  contact_name: string;
  contact_phone: string;
  contact_email: string | null;
  company_name: string | null;
  tax_id: string | null;
  governorate: string | null;
  area: string | null;
  address: string | null;
  needed_by: string | null;
  ip_confirmed: boolean;
  portfolio_consent: boolean;
  subtotal: number;
  setup_total: number;
  vat_rate_at_request: number;
  vat_amount: number;
  total: number;
  client_total: number | null;
  price_mismatch: boolean;
  deposit_amount: number | null;
  deposit_received: boolean;
  status: string;
  manager_note: string | null;
  cancel_reason: string | null;
  customer_note: string | null;
  whatsapp_sent_at: string | null;
  created_at: string;
  order_request_lines: AdminOrderLine[];
  order_request_events: {
    id: string;
    from_status: string | null;
    to_status: string | null;
    note: string | null;
    created_at: string;
  }[];
}

const SELECT = `
  *,
  order_request_lines (
    *,
    order_line_positions ( position_name_ar, area_w_mm, area_h_mm ),
    order_line_options ( group_label_ar, item_label_ar, hex ),
    order_line_texts ( slot, content, font_name_ar, color_hex, pantone_code ),
    order_line_assets ( id, storage_path, original_name, bytes, px_width, px_height, dpi_at_position )
  ),
  order_request_events ( id, from_status, to_status, note, created_at )
`;

export async function fetchOrderByCode(code: string): Promise<AdminOrder | null> {
  const { data, error } = await browserSupabase()
    .from('order_requests')
    .select(SELECT)
    .eq('code', code)
    .maybeSingle();

  if (error) throw error;
  if (!data) return null;

  const order = data as unknown as AdminOrder;
  // PostgREST cannot order an embedded table and a nested one at once, and a
  // job sheet with the lines out of order is a job sheet somebody misreads.
  order.order_request_lines.sort((a, b) => a.line_no - b.line_no);
  for (const line of order.order_request_lines) {
    line.order_line_texts.sort((a, b) => a.slot - b.slot);
  }
  order.order_request_events.sort((a, b) => (a.created_at < b.created_at ? -1 : 1));
  return order;
}
