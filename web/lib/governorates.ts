// المحافظات المصرية السبعة والعشرين.
//
// Ported from BALL STORE (assets/cart.html), where the same list already
// existed. A free-text field here produces "القاهره", "القاهرة", "cairo" and
// "مصر الجديدة" in the same column, and the owner cannot then answer "how much
// do we ship to Alexandria".

export const GOVERNORATES = [
  'القاهرة',
  'الجيزة',
  'الإسكندرية',
  'القليوبية',
  'الدقهلية',
  'الشرقية',
  'الغربية',
  'المنوفية',
  'البحيرة',
  'كفر الشيخ',
  'دمياط',
  'بورسعيد',
  'الإسماعيلية',
  'السويس',
  'شمال سيناء',
  'جنوب سيناء',
  'الفيوم',
  'بني سويف',
  'المنيا',
  'أسيوط',
  'سوهاج',
  'قنا',
  'الأقصر',
  'أسوان',
  'البحر الأحمر',
  'الوادي الجديد',
  'مطروح',
] as const;

export type Governorate = (typeof GOVERNORATES)[number];
