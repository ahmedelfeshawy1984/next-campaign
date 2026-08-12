// رسائل الأخطاء بالعربي.
//
// Same arrangement as ADMIN_ERRORS in web/lib/admin.ts, and for the same
// reason: the database raises a short stable marker, the browser turns it into
// a sentence a human can act on, and the two are never the same string. A
// message written in SQL cannot be reworded without a migration.

const CLINIC_ERRORS: Record<string, string> = {
  // الصلاحيات
  NOT_ALLOWED: 'الصلاحية دي مش متاحة لحسابك.',
  NOT_YOUR_RX: 'الروشتة دي مكتوبة باسم دكتور تاني — تقدر تكتب روشتة جديدة باسمك.',
  NOT_YOURS: 'الكشف ده مكتوب باسم دكتور تاني.',
  LAST_DIRECTOR: 'ده آخر ديريكتور — لازم يفضل شغّال.',
  CANNOT_DISABLE_SELF: 'مش هينفع توقف حسابك بنفسك.',

  // الروشتة
  RX_ISSUED: 'الروشتة دي اتطبعت خلاص ومش بتتعدّل. لو محتاج تعديل، اعمل نسخة معدّلة.',
  RX_EMPTY: 'الروشتة فاضية — ضيف دوا واحد على الأقل.',
  RX_LINE_EMPTY: 'فيه سطر من غير اسم دوا.',
  RX_PREFIX_MISMATCH: 'رقم الروشتة مش متطابق مع حسابك — اقفل التطبيق وافتحه تاني.',
  AMEND_REASON_REQUIRED: 'اكتب سبب التعديل.',
  NO_RX: 'مفيش روشتة بالرقم ده.',

  // المريض والزيارة
  NO_PATIENT: 'المريض ده مش موجود.',
  NAME_REQUIRED: 'اسم المريض مطلوب.',
  NO_VISIT: 'الزيارة دي مش موجودة.',
  NO_DOCTOR: 'اختار دكتور.',
  VISIT_FINAL: 'الزيارة دي خلصت — مش بتتحرك بعد كده.',
  VISIT_TRANSITION_NOT_ALLOWED: 'الانتقال ده مش مسموح من الحالة الحالية.',

  // الفلوس
  BAD_AMOUNT: 'اكتب مبلغ أكبر من صفر.',

  // الحسابات — نفس نص لوحة المحل، عشان نفس الدالة بترفعهم
  BAD_PHONE: 'رقم موبايل مصري غير صحيح.',
  PHONE_TAKEN: 'الرقم ده مسجّل بحساب تاني.',
  PASSWORD_TOO_SHORT: 'كلمة السر لازم ٦ حروف على الأقل.',

  BAD_PAYLOAD: 'البيانات ناقصة — جرّب تاني.',

  // PostgREST's own, when the schema was never exposed. The single most likely
  // setup mistake for this whole feature, and the default message for it says
  // nothing at all.
  PGRST106: 'قاعدة البيانات مش متظبطة: ضيف schema اسمه clinic في '
    + 'Supabase → Settings → API → Exposed schemas.',
};

export function clinicErrorMessage(raw: string): string {
  for (const [marker, message] of Object.entries(CLINIC_ERRORS)) {
    if (raw.includes(marker)) return message;
  }
  // A fetch that never left the building. Worth naming, because the answer is
  // "keep working, it will sync" and not "try again".
  if (/fetch|network|timeout|aborted/i.test(raw)) {
    return 'مفيش نت دلوقتي — الشغل محفوظ على الجهاز وهيترفع لوحده.';
  }
  return raw;
}

/** Narrow an unknown from a catch block into a sentence. */
export function toArabicError(e: unknown): string {
  return clinicErrorMessage(e instanceof Error ? e.message : String(e));
}
