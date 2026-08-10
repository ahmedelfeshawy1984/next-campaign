import { S } from '@/lib/strings';
import type { ProductDetailRow, SpecDef, SpecValue } from '@/lib/types';

/**
 * The spec sheet, generated entirely from spec_defs.
 *
 * Nothing here knows what a mug is. Adding a spec dimension is one
 * `alter table public.products` plus one row in spec_defs — this component
 * renders it without being touched, and the admin form (P4) grows the field
 * from the same row.
 *
 * A null spec is SKIPPED, never printed as 0 or as "—" in the body: unknown is
 * not zero, and a table full of dashes reads as a product nobody has measured.
 */
export default function SpecSheet({
  product,
  defs,
}: {
  product: ProductDetailRow;
  defs: SpecDef[];
}) {
  const read = (key: string): SpecValue => {
    const v = (product as unknown as Record<string, SpecValue>)[key];
    return v === undefined ? null : v;
  };

  const rows = defs
    .map((d) => ({ def: d, value: read(d.key) }))
    .filter((r) => r.value !== null && r.value !== '');

  const extra = Object.entries(product.extra_specs ?? {});
  if (!rows.length && !extra.length) return null;

  // Grouped by section_ar, in spec_defs sort order. An ungrouped spec falls
  // under a blank heading rather than disappearing.
  const sections: { name: string | null; rows: typeof rows }[] = [];
  for (const r of rows) {
    const name = r.def.section_ar ?? null;
    const last = sections[sections.length - 1];
    if (last && last.name === name) last.rows.push(r);
    else sections.push({ name, rows: [r] });
  }

  return (
    <table className="specs">
      <caption className="sr-only">{S.product.specs}</caption>
      <tbody>
        {sections.map((sec, i) => (
          <SectionRows key={`${sec.name ?? 'x'}-${i}`} name={sec.name} rows={sec.rows} />
        ))}
        {extra.length ? (
          <>
            <tr>
              <td className="specs__section" colSpan={2}>
                تفاصيل إضافية
              </td>
            </tr>
            {extra.map(([k, v]) => (
              <tr key={k}>
                <th scope="row">{k}</th>
                <td>{String(v)}</td>
              </tr>
            ))}
          </>
        ) : null}
      </tbody>
    </table>
  );
}

function SectionRows({
  name,
  rows,
}: {
  name: string | null;
  rows: { def: SpecDef; value: SpecValue }[];
}) {
  return (
    <>
      {name ? (
        <tr>
          <td className="specs__section" colSpan={2}>
            {name}
          </td>
        </tr>
      ) : null}
      {rows.map(({ def, value }) => (
        <tr key={def.key}>
          <th scope="row">{def.label_ar}</th>
          <td className={def.kind === 'number' ? 'num' : undefined}>
            {def.kind === 'bool'
              ? value
                ? 'نعم'
                : 'لا'
              : def.unit_ar
                ? `${value} ${def.unit_ar}`
                : String(value)}
          </td>
        </tr>
      ))}
    </>
  );
}
