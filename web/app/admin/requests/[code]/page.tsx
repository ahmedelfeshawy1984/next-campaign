'use client';

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { useParams } from 'next/navigation';
import { fetchOrderByCode, type AdminOrder } from '@/lib/adminOrders';
import { artworkUrl, setOrderStatus, adminErrorMessage } from '@/lib/admin';
import { browserSupabase } from '@/lib/supabase-browser';
import { ORDER_STATUS_AR } from '@/lib/orders';
import { formatPrice, formatQty } from '@/lib/money.js';
import { prettyPhone } from '@/lib/phone.js';
import { whatsappLink } from '@/lib/whatsapp';

// The transitions the machine allows, mirrored so the panel only offers moves
// that will succeed. set_order_status() is still the authority — this list
// exists so the owner is not shown four buttons of which three raise.
const NEXT: Record<string, string[]> = {
  new: ['contacted', 'cancelled'],
  contacted: ['quoted', 'cancelled'],
  quoted: ['artwork_review', 'cancelled'],
  artwork_review: ['artwork_approved', 'quoted', 'cancelled'],
  artwork_approved: ['in_production', 'cancelled'],
  in_production: ['ready', 'cancelled'],
  ready: ['delivered', 'cancelled'],
};

export default function RequestDetail() {
  const { code } = useParams<{ code: string }>();
  const [order, setOrder] = useState<AdminOrder | null | undefined>(undefined);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState('');

  const load = useCallback(() => {
    fetchOrderByCode(code)
      .then(setOrder)
      .catch((e) => {
        setError(adminErrorMessage(String(e.message ?? e)));
        setOrder(null);
      });
  }, [code]);

  useEffect(load, [load]);

  async function move(status: string) {
    setError(null);
    const reason =
      status === 'cancelled' ? window.prompt('سبب الإلغاء؟') : null;
    if (status === 'cancelled' && !reason) return;

    setBusy(true);
    try {
      await setOrderStatus(order!.id, status, note.trim() || null, reason);
      setNote('');
      load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'مش قادرين نغيّر الحالة');
    } finally {
      setBusy(false);
    }
  }

  async function openArtwork(path: string) {
    const url = await artworkUrl(path);
    if (url) window.open(url, '_blank', 'noopener');
    else setError('مش قادرين نفتح الملف ده');
  }

  async function saveField(patch: Record<string, unknown>) {
    setBusy(true);
    try {
      const { error: e } = await browserSupabase()
        .from('order_requests')
        .update(patch)
        .eq('id', order!.id);
      if (e) throw new Error(adminErrorMessage(e.message));
      load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'مش قادرين نحفظ');
    } finally {
      setBusy(false);
    }
  }

  if (order === undefined) return <p className="empty">لحظة…</p>;
  if (!order) return <p className="empty">مفيش طلب بالرقم ده.</p>;

  const wa = whatsappLink(
    order.contact_phone,
    `أهلاً ${order.contact_name}، بخصوص طلبك رقم ${order.code}`
  );

  return (
    <>
      <div className="row" style={{ marginBlockEnd: 6 }}>
        <h1 className="num" dir="ltr" style={{ margin: 0 }}>
          {order.code}
        </h1>
        <span className="chip chip--on">{ORDER_STATUS_AR[order.status] ?? order.status}</span>
        <span className="spacer" />
        <Link href={`/admin/requests/${order.code}/print`} className="btn btn--ghost btn--sm">
          أمر شغل للطباعة
        </Link>
        {wa ? (
          <a className="btn btn--brand btn--sm" href={wa} target="_blank" rel="noopener noreferrer">
            واتساب
          </a>
        ) : null}
      </div>

      {error ? <p className="notice notice--warn">{error}</p> : null}

      {order.price_mismatch ? (
        <p className="notice notice--warn">
          العميل شاف <span className="num">{formatPrice(order.client_total)}</span> وإحنا
          حسبنا <span className="num">{formatPrice(order.total)}</span>. الأسعار اتغيّرت
          والصفحة كانت مفتوحة عنده — اذكرها في المكالمة.
        </p>
      ) : null}

      <div className="admin__cols">
        <div>
          {order.order_request_lines.map((line) => (
            <article key={line.id} className="panel" style={{ marginBlockEnd: 14 }}>
              <div className="row">
                <strong>
                  <span className="num">{line.line_no}.</span> {line.product_name_ar}
                </strong>
                <span className="spacer" />
                <strong className="num">{formatPrice(line.line_total)}</strong>
              </div>

              <div className="cfg__hint">
                <span className="num">{formatQty(line.qty)}</span> قطعة ×{' '}
                <span className="num">{formatPrice(line.unit_price_at_request)}</span>
                {Number(line.setup_fee_at_request) > 0 ? (
                  <>
                    {' '}
                    + تجهيز{' '}
                    <span className="num">{formatPrice(line.setup_fee_at_request)}</span>
                  </>
                ) : null}
              </div>

              <table className="specs" style={{ marginBlockStart: 10 }}>
                <tbody>
                  {line.method_name_ar ? (
                    <tr>
                      <th scope="row">الطباعة</th>
                      <td>
                        {line.method_name_ar}
                        {line.colors_count && line.colors_count > 1 ? (
                          <>
                            {' — '}
                            <span className="num">{line.colors_count}</span> ألوان
                          </>
                        ) : null}
                      </td>
                    </tr>
                  ) : null}
                  {line.order_line_positions.length ? (
                    <tr>
                      <th scope="row">مكان الطباعة</th>
                      <td>
                        {line.order_line_positions
                          .map((p) =>
                            p.area_w_mm
                              ? `${p.position_name_ar} (${Number(p.area_w_mm)}×${Number(p.area_h_mm)} مم)`
                              : p.position_name_ar
                          )
                          .join(' + ')}
                      </td>
                    </tr>
                  ) : null}
                  {line.order_line_options.map((o) => (
                    <tr key={o.group_label_ar}>
                      <th scope="row">{o.group_label_ar}</th>
                      <td>
                        {o.hex ? (
                          <span
                            className="swatch"
                            style={{
                              background: o.hex,
                              inlineSize: 16,
                              blockSize: 16,
                              display: 'inline-block',
                              verticalAlign: 'middle',
                              marginInlineEnd: 6,
                            }}
                          />
                        ) : null}
                        {o.item_label_ar}
                      </td>
                    </tr>
                  ))}
                  {line.order_line_texts.map((t) => (
                    <tr key={t.slot}>
                      <th scope="row">
                        النص <span className="num">{t.slot}</span>
                      </th>
                      <td>
                        {/* Printed exactly as typed, and never "tidied": a
                            missing space in a company name is the customer's
                            decision until they say otherwise. */}
                        <strong>{t.content}</strong>
                        {t.font_name_ar ? (
                          <span className="cfg__hint"> — خط {t.font_name_ar}</span>
                        ) : null}
                      </td>
                    </tr>
                  ))}
                  {line.notes ? (
                    <tr>
                      <th scope="row">ملاحظات السطر</th>
                      <td>{line.notes}</td>
                    </tr>
                  ) : null}
                </tbody>
              </table>

              {line.order_line_assets.length ? (
                <ul className="cfg__files">
                  {line.order_line_assets.map((a) => (
                    <li key={a.id} className="cfg__file">
                      <span className="cfg__file-ext">
                        {(a.original_name?.split('.').pop() ?? '?').toUpperCase()}
                      </span>
                      <span className="cfg__file-body">
                        <strong>{a.original_name ?? a.storage_path}</strong>
                        <span className="cfg__hint num" dir="ltr">
                          {a.bytes ? `${(a.bytes / 1024).toFixed(0)} KB` : ''}
                          {a.px_width ? ` · ${a.px_width}×${a.px_height}` : ''}
                          {a.dpi_at_position ? ` · ${Number(a.dpi_at_position)} dpi` : ''}
                        </span>
                        {a.dpi_at_position && Number(a.dpi_at_position) < 150 ? (
                          <span className="cfg__file-warn">
                            دقة أقل من ١٥٠ — العميل اتحذّر قبل الإرسال
                          </span>
                        ) : null}
                      </span>
                      <button
                        type="button"
                        className="btn btn--ghost btn--sm"
                        onClick={() => openArtwork(a.storage_path)}
                      >
                        افتح
                      </button>
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="cfg__hint" style={{ marginBlockStart: 8 }}>
                  مفيش ملفات مرفوعة على السطر ده.
                </p>
              )}
            </article>
          ))}

          <div className="panel">
            <div className="panel__title">الحساب</div>
            <table className="specs">
              <tbody>
                <tr>
                  <th scope="row">الإجمالي قبل الضريبة</th>
                  <td className="num">
                    {formatPrice(Number(order.subtotal) + Number(order.setup_total))}
                  </td>
                </tr>
                <tr>
                  <th scope="row">
                    الضريبة (<span className="num">{Number(order.vat_rate_at_request) * 100}%</span>)
                  </th>
                  <td className="num">{formatPrice(order.vat_amount)}</td>
                </tr>
                <tr>
                  <th scope="row">الإجمالي</th>
                  <td className="num">
                    <strong>{formatPrice(order.total)}</strong>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        {/* --------------------------------------------------------- side -- */}
        <div>
          <div className="panel">
            <div className="panel__title">العميل</div>
            <table className="specs">
              <tbody>
                <tr>
                  <th scope="row">الاسم</th>
                  <td>{order.contact_name}</td>
                </tr>
                {order.company_name ? (
                  <tr>
                    <th scope="row">الشركة</th>
                    <td>{order.company_name}</td>
                  </tr>
                ) : null}
                {order.tax_id ? (
                  <tr>
                    <th scope="row">الرقم الضريبي</th>
                    <td className="num" dir="ltr">
                      {order.tax_id}
                    </td>
                  </tr>
                ) : null}
                <tr>
                  <th scope="row">الموبايل</th>
                  <td>
                    <a href={`tel:${order.contact_phone}`} className="num" dir="ltr">
                      {prettyPhone(order.contact_phone)}
                    </a>
                  </td>
                </tr>
                {order.contact_email ? (
                  <tr>
                    <th scope="row">الإيميل</th>
                    <td dir="ltr">{order.contact_email}</td>
                  </tr>
                ) : null}
                {order.governorate ? (
                  <tr>
                    <th scope="row">المحافظة</th>
                    <td>
                      {order.governorate}
                      {order.address ? ` — ${order.address}` : ''}
                    </td>
                  </tr>
                ) : null}
                {order.needed_by ? (
                  <tr>
                    <th scope="row">مطلوب قبل</th>
                    <td className="num" dir="ltr">
                      {order.needed_by}
                    </td>
                  </tr>
                ) : null}
                {order.customer_note ? (
                  <tr>
                    <th scope="row">ملاحظات العميل</th>
                    <td>{order.customer_note}</td>
                  </tr>
                ) : null}
                <tr>
                  <th scope="row">إقرار حق الشعار</th>
                  <td>{order.ip_confirmed ? 'موافق' : 'لأ'}</td>
                </tr>
                <tr>
                  <th scope="row">عرض الشغل في أعمالنا</th>
                  <td>{order.portfolio_consent ? 'موافق' : 'مش موافق'}</td>
                </tr>
              </tbody>
            </table>
          </div>

          <div className="panel">
            <div className="panel__title">الحالة</div>
            <label className="field">
              <span>ملاحظة تتسجّل مع الحركة</span>
              <input type="text" value={note} onChange={(e) => setNote(e.target.value)} />
            </label>
            <div className="chip-row">
              {(NEXT[order.status] ?? []).map((s) => (
                <button
                  key={s}
                  type="button"
                  className={`btn btn--sm ${s === 'cancelled' ? 'btn--ghost' : 'btn--brand'}`}
                  disabled={busy}
                  onClick={() => move(s)}
                >
                  {ORDER_STATUS_AR[s]}
                </button>
              ))}
              {!(NEXT[order.status] ?? []).length ? (
                <span className="cfg__hint">الطلب في حالة نهائية.</span>
              ) : null}
            </div>
            {order.cancel_reason ? (
              <p className="notice notice--warn" style={{ marginBlockStart: 10 }}>
                سبب الإلغاء: {order.cancel_reason}
              </p>
            ) : null}
          </div>

          <div className="panel">
            <div className="panel__title">العربون</div>
            <div className="row">
              <input
                className="cfg__text"
                style={{ maxInlineSize: 140 }}
                type="number"
                dir="ltr"
                defaultValue={order.deposit_amount ?? ''}
                placeholder="المبلغ"
                onBlur={(e) =>
                  saveField({ deposit_amount: e.target.value ? Number(e.target.value) : null })
                }
              />
              <label className="check" style={{ margin: 0 }}>
                <input
                  type="checkbox"
                  checked={order.deposit_received}
                  onChange={(e) => saveField({ deposit_received: e.target.checked })}
                />
                <span>اتحصّل</span>
              </label>
            </div>
            <p className="cfg__hint" style={{ marginBlockStart: 8 }}>
              العربون مش حالة — ممكن يتحصّل في أي وقت، فهو خانة مستقلة عن مسار الطلب.
            </p>
          </div>

          <div className="panel">
            <div className="panel__title">التاريخ</div>
            <ol className="admin__events">
              {order.order_request_events.map((e) => (
                <li key={e.id}>
                  <span className="num" dir="ltr">
                    {new Date(e.created_at).toLocaleString('en-GB')}
                  </span>
                  <br />
                  {e.from_status
                    ? `${ORDER_STATUS_AR[e.from_status]} ← ${ORDER_STATUS_AR[e.to_status ?? '']}`
                    : (e.note ?? ORDER_STATUS_AR[e.to_status ?? ''])}
                  {e.from_status && e.note ? <span className="cfg__hint"> — {e.note}</span> : null}
                </li>
              ))}
            </ol>
          </div>
        </div>
      </div>
    </>
  );
}
