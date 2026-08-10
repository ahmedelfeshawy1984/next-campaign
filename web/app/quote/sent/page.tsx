import type { Metadata } from 'next';
import OrderSent from '@/components/OrderSent';
import { getSiteSettings } from '@/lib/queries';
import { S } from '@/lib/strings';

export const metadata: Metadata = {
  title: 'تم إرسال الطلب',
  robots: { index: false, follow: false },
};

export default async function SentPage() {
  const settings = await getSiteSettings();
  return (
    <section className="section">
      <div className="wrap">
        <OrderSent
          whatsappPhone={settings?.whatsapp_phone ?? null}
          currency={settings?.currency ?? S.common.currency}
        />
      </div>
    </section>
  );
}
