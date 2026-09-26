// إعدادات Family Love — مشروع Supabase مستقل تمامًا عن الشوب والعيادة.
//
// عمدًا بلا أي fallback على env.ts بتاع الشوب (خلافًا لـ clinicEnv): سر توقيع
// الـ JWT هنا بيفتح صلاحيات حسابات الأطفال، فأي تسرب بينه وبين مشروع تاني
// خطر حقيقي، مش مجرد تكرار كود. لو المتغيرات ناقصة، الشاشات تعرض "غير مُعد"
// بدل ما تشتغل على قاعدة بيانات حد تاني.

const PLACEHOLDERS = ['', 'paste-', 'xxxx', 'your-', 'changeme'];

function isPlaceholder(v: string | undefined): boolean {
  if (!v) return true;
  const lower = v.toLowerCase();
  return PLACEHOLDERS.some((p) => p !== '' && lower.startsWith(p));
}

export const familyLoveEnv = {
  supabaseUrl: process.env.NEXT_PUBLIC_FAMILYLOVE_SUPABASE_URL ?? '',
  supabaseAnonKey: process.env.NEXT_PUBLIC_FAMILYLOVE_SUPABASE_ANON_KEY ?? '',
  /** سيرفر بس — ممنوع يوصل لأي بندل بيتبعت للمتصفح. */
  serviceRoleKey: process.env.FAMILYLOVE_SUPABASE_SERVICE_ROLE_KEY ?? '',
  /** سيرفر بس — بيوقّع/يتحقق من JWT الأجهزة. */
  jwtSecret: process.env.FAMILYLOVE_SUPABASE_JWT_SECRET ?? '',
  vapidPublicKey: process.env.NEXT_PUBLIC_FAMILYLOVE_VAPID_PUBLIC_KEY ?? '',
  /** سيرفر بس. */
  vapidPrivateKey: process.env.FAMILYLOVE_VAPID_PRIVATE_KEY ?? '',
};

export const familyLoveIsConfigured =
  !isPlaceholder(familyLoveEnv.supabaseUrl) && !isPlaceholder(familyLoveEnv.supabaseAnonKey);

export const familyLoveServerIsConfigured =
  familyLoveIsConfigured &&
  !isPlaceholder(familyLoveEnv.serviceRoleKey) &&
  !isPlaceholder(familyLoveEnv.jwtSecret);
