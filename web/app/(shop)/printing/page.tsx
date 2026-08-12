import type { Metadata } from 'next';
import Link from 'next/link';
import { S } from '@/lib/strings';
import { getPrintMethods, getSiteSettings } from '@/lib/queries';
import { formatPrice } from '@/lib/money';
import type { PrintColorModel } from '@/lib/types';

export const revalidate = 3600;

export const metadata: Metadata = {
  title: S.nav.printing,
  description:
    'الفرق بين السلك سكرين والحفر بالليزر والتطريز وطباعة UV والسبليميشن — وأنهي طريقة تناسب منتجك وكميتك.',
  alternates: { canonical: '/printing' },
};

// What the customer actually needs to know about each colour model, in one
// sentence. This is the difference between a page that ranks and a page that
// lists eleven words.
const COLOR_MODEL_NOTE: Record<PrintColorModel, string> = {
  spot: 'بتدفع لكل لون على حدة — كليشيه لكل لون، وسعر إضافي للقطعة عن كل لون زيادة. أوفر ما تكون في اللوجوهات البسيطة والكميات الكبيرة.',
  full_color: 'ألوان كاملة بسعر واحد مهما كان التصميم. أنسب للصور والتدرجات اللونية.',
  single_tone: 'مالهاش لون — بتشتغل على الخامة نفسها، فالنتيجة بلون المعدن أو الخشب تحت السطح. عمرها ما بتمسح.',
  thread: 'بتتحسب بعدد ألوان الخيط وكثافة الغرز. الرسم الرقمي (ديچيتايزنج) بيتعمل مرة واحدة على التصميم.',
};

export default async function PrintingPage() {
  const [methods, settings] = await Promise.all([getPrintMethods(), getSiteSettings()]);
  const currency = settings?.currency ?? S.common.currency;

  return (
    <>
      <section className="section section--tight section--surface">
        <div className="wrap">
          <h1>{S.nav.printing}</h1>
          <p className="lead">
            مش كل منتج بيتطبع بنفس الطريقة، ومش كل طريقة مناسبة لكل كمية. دي الطرق اللي بنشتغل
            بيها، وإمتى كل واحدة بتبقى الاختيار الصح.
          </p>
        </div>
      </section>

      <section className="section">
        <div className="wrap">
          <div className="grid grid--wide">
            {methods.map((m) => (
              <article key={m.code} className="tile">
                <h2 className="tile__title" style={{ fontSize: '1.05rem' }}>
                  {m.name_ar}
                  {m.name_en ? (
                    <span
                      dir="ltr"
                      style={{ fontWeight: 500, color: 'var(--ink-faint)', fontSize: '0.82rem' }}
                    >
                      {' '}
                      {m.name_en}
                    </span>
                  ) : null}
                </h2>
                {m.blurb_ar ? <p className="tile__blurb">{m.blurb_ar}</p> : null}
                <p className="tile__blurb" style={{ marginBlockStart: 8 }}>
                  {COLOR_MODEL_NOTE[m.color_model]}
                </p>

                <div className="chip-row" style={{ marginBlockStart: 12 }}>
                  {Number(m.default_setup_fee) > 0 ? (
                    <span className="chip">
                      {S.product.setupFee}{' '}
                      <span className="num">
                        {formatPrice(m.default_setup_fee, currency)}
                      </span>
                    </span>
                  ) : (
                    <span className="chip">من غير كليشيه</span>
                  )}
                  {m.default_max_colors ? (
                    <span className="chip">
                      حتى <span className="num">{m.default_max_colors}</span> ألوان
                    </span>
                  ) : null}
                  {m.needs_vector ? (
                    <span className="chip chip--warn">{S.product.needsVector}</span>
                  ) : null}
                </div>

                <p style={{ marginBlockStart: 12, marginBlockEnd: 0 }}>
                  <Link href={`/corporate?method=${m.code}`} className="btn btn--ghost btn--sm">
                    شوف المنتجات اللي بتتطبع كده
                  </Link>
                </p>
              </article>
            ))}
          </div>

          <div className="notice" style={{ marginBlockStart: 24 }}>
            الأسعار المذكورة هنا رسوم تجهيز افتراضية — كل منتج ممكن يكون له رسوم مختلفة، وبتلاقيها
            على صفحته.{' '}
            {settings?.artwork_service_fee
              ? `ولو معندكش ملف vector، بنعمله لك بـ ${formatPrice(settings.artwork_service_fee, currency)}.`
              : ''}
          </div>
        </div>
      </section>
    </>
  );
}
