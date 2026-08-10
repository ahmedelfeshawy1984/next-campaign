import { S } from '@/lib/strings';
import ProductCard from './ProductCard';
import type { ProductCardRow, SpecDef } from '@/lib/types';

export default function ProductGrid({
  products,
  cardSpecs = [],
  currency = 'ج.م',
  emptyAction,
}: {
  products: ProductCardRow[];
  cardSpecs?: SpecDef[];
  currency?: string;
  emptyAction?: React.ReactNode;
}) {
  if (!products.length) {
    return (
      <div className="empty">
        <h3>{S.catalog.noResults}</h3>
        <p>{S.catalog.noResultsBody}</p>
        {emptyAction}
      </div>
    );
  }

  return (
    <div className="grid">
      {products.map((p) => (
        <ProductCard key={p.id} product={p} cardSpecs={cardSpecs} currency={currency} />
      ))}
    </div>
  );
}
