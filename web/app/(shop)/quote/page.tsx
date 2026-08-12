import type { Metadata } from 'next';
import QuoteBasket from '@/components/QuoteBasket';
import { getSiteSettings } from '@/lib/queries';

export const metadata: Metadata = {
  title: 'عرض السعر',
  // The basket is personal and has nothing for a crawler to index.
  robots: { index: false, follow: true },
};

export default async function QuotePage() {
  const settings = await getSiteSettings();

  return (
    <section className="section section--tight">
      <div className="wrap">
        <h1>عرض السعر</h1>
        <p className="lead">
          راجع المنتجات والكميات، اكتب بياناتك، وابعت. {settings?.quote_promise_ar ?? ''}
        </p>
        <QuoteBasket />
      </div>
    </section>
  );
}
