# Family Love — اللي باقي قبل النشر الفعلي

الكود كله (قاعدة البيانات، الـ API، الواجهة، PWA) جاهز ومتفحوص محليًا. اللي
باقي دلوقتي حاجتين بس: **حسابات/قرارات بيزنس محتاجة منك**، و**خطوات نشر يدوية**
مينفعش يعملها كود لوحده. الملف ده قائمة عملية بالاتنين.

---

## ٠. تفعيل حساب مسؤول (لإدارة الإعلانات)

صفحة `/family-love/admin` (إضافة/إيقاف/حذف إعلانات البانر) محصورة بحساب
عليه `accounts.is_platform_admin = true`. مفيش واجهة لترقية حساب لأدمن عمدًا —
فعل نادر مش يستاهل شاشة. من Supabase dashboard:

```sql
update public.accounts set is_platform_admin = true where phone = '01xxxxxxxxx';
```

---

## ١. حسابات لازم تتعمل (مش قرارات تقنية)

### مشروع Supabase مستقل لـ Family Love
1. [supabase.com/dashboard](https://supabase.com/dashboard) → **New project**
   (منفصل تمامًا عن مشروع الشوب/العيادة — راجع خطة التنفيذ لو عايز تفهم ليه).
2. Settings → API → انسخ **Project URL** و**anon key** و**service_role key**
   و**JWT Secret**.
3. حط المتغيرات دي في Vercel (Environment Variables):
   - `NEXT_PUBLIC_FAMILYLOVE_SUPABASE_URL`
   - `NEXT_PUBLIC_FAMILYLOVE_SUPABASE_ANON_KEY`
   - `FAMILYLOVE_SUPABASE_SERVICE_ROLE_KEY` (سري — سيرفر بس)
   - `FAMILYLOVE_SUPABASE_JWT_SECRET` (سري — سيرفر بس)
4. SQL Editor → شغّل ملفات `supabase/family-love/migrations/*.sql` بالترتيب
   (0001 لحد 0006)، وبعدين `supabase/family-love/seed.sql`.
5. **مهم عشان شريط الباص يبقى حي فعليًا**: Database → Replication → فعّل
   Realtime على جدول `task_occurrences`. من غيرها الشاشة بتشتغل عادي بس
   محتاجة تحديث الصفحة يدويًا بدل ما تتحرك لحظة ما الطفل يضغط.

### مفاتيح Web Push (VAPID) — **ده مش محتاج حساب خارجي خالص**
التنبيهات الفعلية (SOS، الموقع، الرسايل، التذكيرات) شغالة بالكود من دلوقتي
(`web/lib/family-love/push.ts`)، بس محتاجة مفتاحين توليدهم مرة واحدة بس:

```bash
cd web && npx web-push generate-vapid-keys
```

حط الناتج في Vercel:
- `NEXT_PUBLIC_FAMILYLOVE_VAPID_PUBLIC_KEY`
- `FAMILYLOVE_VAPID_PRIVATE_KEY` (سري)
- `FAMILYLOVE_VAPID_SUBJECT` = `mailto:بريدك@دومينك.com` (اختياري، له قيمة افتراضية)

لحد ما المتغيرات دي متظبطة، زرار 🔔 مش هيظهر خالص في الواجهة (مفيش تنبيهات
وهمية أو معطلة — الميزة بتختفي بدل ما تفشل بصمت).

### إرسال التنبيهات المجدولة (Vercel Cron)
`web/vercel.json` معمول فيه Cron يضرب `cron/dispatch-reminders` **كل دقيقة**.
⚠️ **مهم**: خطة Vercel المجانية (Hobby) بتسمح بـCron **مرة واحدة باليوم بس** —
لازم خطة Pro عشان الجدولة الدقيقة دي تشتغل فعليًا. لو قاعد على Hobby مؤقتًا،
غيّر `"schedule"` في `web/vercel.json` لحاجة يومية (`"0 6 * * *"` مثلًا) لحد
ما تترقّى، أو استخدم خدمة خارجية (cron-job.org) تضرب نفس الرابط كل دقيقة.

### مزوّد OTP (إرسال كود التأكيد)
دلوقتي بيشتغل بـ "console provider" — بيطبع الكود في اللوج بدل ما يبعت SMS
حقيقي. ده كويس للتجربة المحلية بس، **مش صالح للنشر الفعلي**. لازم تختار واحد:
- **Twilio Verify** (موصى بيه — نفس الـ API لـ SMS وWhatsApp): افتح حساب،
  اعمل Verify Service، وحط:
  - `FAMILYLOVE_TWILIO_ACCOUNT_SID`
  - `FAMILYLOVE_TWILIO_AUTH_TOKEN`
  - `FAMILYLOVE_TWILIO_VERIFY_SID`
  - `FAMILYLOVE_OTP_CHANNEL` = `sms` أو `whatsapp`
- أو بوابة SMS محلية / WhatsApp Cloud API مباشرة — التبديل محصور في ملف واحد:
  `web/lib/family-love/otpProvider.ts`.

### بوابة دفع لمستخدمي آيفون/الويب
اللي بيوصلوا عن طريق الرابط المشارك (مش من جوجل بلاي) محتاجين بوابة دفع ويب
منفصلة (Stripe/Paymob/Fawry). لسه مش متوصلة بالكود — `subscriptions.platform =
'web'` جاهز في قاعدة البيانات، لكن مسارات `billing/web/checkout` و
`billing/web/webhook` من الخطة الأصلية لسه مبنيتش (اتأجلت لحد ما تختار البوابة).

### Google Play Billing (اشتراك أندرويد)
محتاج:
- Service Account على Google Play Console بصلاحية الوصول لـ Play Developer API.
- تفعيل **Real-time Developer Notifications** (Pub/Sub) عشان تحديثات
  الاشتراك (تجديد/إلغاء) توصل حتى لو التطبيق مقفول.
- مسارات `billing/play/verify` و`billing/play/webhook` من الخطة الأصلية لسه
  مبنيتش (محتاجة الحساب ده الأول).

### مدة التجربة المجانية
دلوقتي ٤٥ يوم (`family_love_settings.trial_days`) — قابلة للتعديل من قاعدة
البيانات مباشرة، مفيش داعي لتعديل كود.

---

## ٢. تغليف Android (TWA) عبر Bubblewrap

الكود جاهز يشتغل كـ PWA عادي على الويب دلوقتي (`/family-love`). عشان تترفع
على Google Play:

1. ثبّت [Bubblewrap CLI](https://github.com/GoogleChromeLabs/bubblewrap).
2. `bubblewrap init --manifest https://<دومينك>/family-love.webmanifest`
3. Bubblewrap هيطلب منك مفتاح توقيع (keystore) — لو معندكش، هو بيعملك واحد.
4. بعد التوقيع، خد الـ SHA-256 fingerprint بتاع الشهادة وحط ملف
   `.well-known/assetlinks.json` في `web/public/` (المسار ده **متعمَلش لسه**
   عمدًا — لازم بيانات حقيقية من الخطوة دي، مش قيم وهمية).
5. `bubblewrap build` → ينتج APK/AAB جاهز للرفع على Play Console.

---

## ٣. متطلبات رفع Google Play الإدارية (مش كود خالص)

- **رابط سياسة الخصوصية**: لازم صفحة حقيقية توضح جمع الموقع (لحظي بس) والدفع.
- **Data Safety Form**: صرّح إن التطبيق بيجمع Location (one-time) وPersonal
  info (رقم تليفون) — الغرض: App functionality، مفيش مشاركة مع طرف تالت.
- **قناة اختبار للاشتراكات** (Internal Testing Track) قبل ما تفعّل الدفع
  الحقيقي على الـ Production.

---

## ٤. حاجات اتأجلت عمدًا (مش نسيان)

- **Live Location المستمر بالخلفية** (تتبع مستمر بدل ضغطة زرار) — يحتاج
  Background Location Declaration في Play Console + مراجعة إضافية من جوجل.
- **مشاركة صور/فيديو بين الطفل والأهل** — يحتاج فحص محتوى (CSAM scanning)
  وآلية إبلاغ، تعقيد سياسات Child Safety مش يستاهل في أول نسخة.

القرارين دول اتاخدوا بعد نقاش مطوّل عن سياسات Google Play، وموثقين في خطة
التنفيذ الأصلية — راجعهم قبل ما تضيفهم بدري.

---

## ٥. الاختبار محليًا

```bash
npm run db:check:family-love   # فحص قاعدة البيانات (RLS، RPCs، تطابق التكرار)
npm run typecheck              # كل المستودع
npm run check:rtl              # خصائص RTL منطقية بس
npm run build                  # بناء إنتاجي كامل
npm run dev                    # تشغيل محلي — افتح /family-love
```

اختبار الإشعارات (Web Push) على آيفون حقيقي لازم يدوي — التطبيق لازم يتضاف
للشاشة الرئيسية ويتفتح منها مرة على الأقل قبل ما يطلب صلاحية الإشعارات.
