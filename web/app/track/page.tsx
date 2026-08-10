import type { Metadata } from 'next';
import TrackForm from '@/components/TrackForm';
import { getSiteSettings } from '@/lib/queries';
import { S } from '@/lib/strings';

export const metadata: Metadata = {
  title: 'تتبع الطلب',
  robots: { index: false, follow: true },
};

export default async function TrackPage() {
  const settings = await getSiteSettings();
  return (
    <section className="section">
      <div className="wrap">
        <h1>تتبع الطلب</h1>
        <p className="lead">
          لو طلبت من الجهاز ده، البيانات هتتملّي لوحدها. ولو من جهاز تاني،
          محتاج رقم الطلب الداخلي والموبايل اللي طلبت بيه.
        </p>
        <TrackForm currency={settings?.currency ?? S.common.currency} />
      </div>
    </section>
  );
}
