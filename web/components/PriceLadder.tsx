import { S } from '@/lib/strings';
import { formatPrice, formatQty, savingPercent } from '@/lib/money';
import type { PriceTier } from '@/lib/types';

/**
 * The ladder, as a table.
 *
 * In P2 this becomes a control — drag the quantity, watch the rung light up
 * and the total move. Until then it is still the single most persuasive thing
 * on the page, because it answers the only question a corporate buyer has:
 * "and if I take 250?"
 *
 * Half-open intervals: the upper bound of a rung is the next rung's min_qty,
 * never a stored max. The label is built from the neighbour for that reason.
 */
export default function PriceLadder({
  tiers,
  moq,
  currency = 'ج.م',
}: {
  tiers: PriceTier[];
  moq: number;
  currency?: string;
}) {
  if (!tiers.length) return null;

  const sorted = [...tiers].sort((a, b) => a.min_qty - b.min_qty);
  // The honest baseline for "you save X%" is what this actually costs at the
  // cheapest quantity you are allowed to order — not the top of the ladder.
  const base = sorted.find((t) => t.min_qty <= moq) ?? sorted[0];

  return (
    <table className="ladder">
      <caption className="sr-only">{S.product.priceLadder}</caption>
      <thead>
        <tr>
          <th scope="col">{S.product.quantity}</th>
          <th scope="col">{S.product.unitPrice}</th>
          <th scope="col">{S.product.save}</th>
        </tr>
      </thead>
      <tbody>
        {sorted.map((t, i) => {
          const next = sorted[i + 1];
          const range = next
            ? `${formatQty(t.min_qty)} – ${formatQty(next.min_qty - 1)}`
            : `${formatQty(t.min_qty)}+`;
          const saving = savingPercent(base.unit_price, t.unit_price);
          const isBest = i === sorted.length - 1 && sorted.length > 1;

          return (
            <tr key={t.min_qty} className={isBest ? 'ladder__best' : undefined}>
              <th scope="row" className="num" style={{ fontWeight: 600 }}>
                {range}
              </th>
              <td className="num">{formatPrice(t.unit_price, currency)}</td>
              <td className="ladder__save num">{saving ? `${saving}%` : '—'}</td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}
