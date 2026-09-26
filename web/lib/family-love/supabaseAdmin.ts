// عميل السيرفر بمفتاح service role — بيتخطى RLS بالكامل، فمكانه الوحيد
// مسارات web/app/api/family-love/**، وممنوع يوصل لأي كود بيتبعت للمتصفح.
// خلافًا لعميل الشوب/العيادة، معندوش مستخدم Supabase Auth خالص — كل التسجيل
// بيحصل عن طريق الدوال في supabase/family-love/migrations اللي بتتنادى هنا.
//
// ملاحظة: عمدًا بلا حزمة `server-only` (المستودع مفيهوش أي اعتماديات زيادة
// عن next/react/supabase-js) — الحماية الفعلية إن الملف ده ميتفتحش غير من
// جوه web/app/api/family-love/**، اللي أصلاً كود سيرفر بحكم Next.js نفسه.
import { createClient } from '@supabase/supabase-js';
import { familyLoveEnv, familyLoveServerIsConfigured } from './env';

let cached: ReturnType<typeof createClient> | null = null;

export function familyLoveAdmin(): ReturnType<typeof createClient> {
  if (!familyLoveServerIsConfigured) {
    throw new Error('Family Love: Supabase server config missing');
  }
  if (!cached) {
    cached = createClient(familyLoveEnv.supabaseUrl, familyLoveEnv.serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  }
  return cached;
}
