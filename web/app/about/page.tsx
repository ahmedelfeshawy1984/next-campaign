import type { Metadata } from 'next';
import { S } from '@/lib/strings';
import { getSiteSettings } from '@/lib/queries';
import { prettyPhone } from '@/lib/phone';
import { whatsappLink } from '@/lib/whatsapp';

export const revalidate = 3600;

export const metadata: Metadata = {
  title: S.nav.about,
  description:
    'نكست كامباين — مطبوعات وهدايا دعائية للشركات في مصر، وهدايا شخصية باسم صاحبها.',
  alternates: { canonical: '/about' },
};

export default async function AboutPage() {
  const settings = await getSiteSettings();
  const wa = whatsappLink(settings?.whatsapp_phone);

  return (
    <section className="section">
      <div className="wrap" style={{ maxInlineSize: 760 }}>
        <h1>{S.nav.about}</h1>
        <p className="lead">{settings?.tagline_ar ?? S.tagline}</p>

        <p>
          بنشتغل في المطبوعات والهدايا الدعائية للشركات: مجات وأقلام وأجندات وتيشرتات وفلاشات
          وشنط، مطبوعة أو محفورة بلوجو شركتك. وبنعمل كمان الهدايا الشخصية — القطعة الواحدة اللي
          عليها اسم أو كلمة أو معايدة.
        </p>

        <h2>ليه الأسعار ظاهرة على الموقع</h2>
        <p>
          لإن أول سؤال بيتسأل هو «بكام؟»، وتأجيل الإجابة لمكالمة تليفون بيضيّع وقت الطرفين. كل
          منتج هنا عليه سعر القطعة عند كل كمية، ورسوم الكليشيه، والحد الأدنى للطلب — تقدر تحسب
          ميزانيتك قبل ما تكلّم حد.
        </p>

        <h2>الملفات والمعاينة</h2>
        <p>
          بنراجع كل ملف قبل التنفيذ. لو الملف مش بجودة كافية للمقاس المطلوب، بنقولك قبل ما ننفّذ
          مش بعديها، وبنبعتلك معاينة نهائية لازم توافق عليها. الألوان على الشاشة تقريبية — المرجع
          الوحيد هو كود بانتون أو عينة مطبوعة.
        </p>

        <h2>{S.nav.contact}</h2>
        <div className="stack">
          {settings?.hotline ? (
            <div>
              تليفون:{' '}
              <a href={`tel:${settings.hotline}`} className="num" dir="ltr">
                {prettyPhone(settings.hotline)}
              </a>
            </div>
          ) : null}
          {settings?.email ? (
            <div>
              إيميل:{' '}
              <a href={`mailto:${settings.email}`} dir="ltr">
                {settings.email}
              </a>
            </div>
          ) : null}
          {settings?.address_ar ? <div>العنوان: {settings.address_ar}</div> : null}
          {settings?.working_hours_ar ? <div>مواعيد العمل: {settings.working_hours_ar}</div> : null}
        </div>

        {wa ? (
          <p style={{ marginBlockStart: 20 }}>
            <a className="btn btn--brand" href={wa} target="_blank" rel="noopener noreferrer">
              {S.common.whatsapp}
            </a>
          </p>
        ) : (
          <p className="notice" style={{ marginBlockStart: 20 }}>
            بيانات التواصل لسه مش متسجّلة في الإعدادات — املاها من{' '}
            <code>site_settings</code> في Supabase.
          </p>
        )}
      </div>
    </section>
  );
}
