import type { QuoteError } from './pricing.types';

// Server-side truth, translated once.
//
// price_quote() returns stable codes rather than sentences, for the same reason
// the sibling project's PRED_LOCKED / RATE_LIMITED markers do: the database
// knows WHAT is wrong, the interface knows how to SAY it, and a code survives a
// copy edit. This map is the only place a customer-facing wording lives.

const MESSAGES: Record<QuoteError, string> = {
  PRODUCT_NOT_FOUND: 'المنتج ده مش موجود.',
  QTY_INVALID: 'اكتب كمية صحيحة.',
  QTY_BELOW_MOQ: 'الكمية أقل من الحد الأدنى للطلب.',
  NO_PRICE_TIER: 'مفيش سعر للكمية دي — كلمنا ونظبطهالك.',
  OPTION_UNAVAILABLE: 'الخيار اللي اخترته خلص حالياً.',
  OPTION_NOT_ON_PRODUCT: 'في اختيار قديم في الصفحة — حدّث الصفحة من فضلك.',
  METHOD_NOT_SUPPORTED: 'طريقة الطباعة دي مش متاحة للمنتج ده.',
  TOO_MANY_COLORS: 'عدد الألوان أكتر من اللي الطريقة دي بتسمح بيه.',
  QTY_BELOW_METHOD_MIN: 'الطريقة دي ليها حد أدنى أعلى من الكمية اللي اخترتها.',
  TOO_MANY_POSITIONS: 'اخترت أماكن طباعة أكتر من المسموح للمنتج ده.',
  POSITION_METHOD_NOT_ALLOWED: 'الطريقة دي مش بتشتغل على المكان اللي اخترته.',
  POSITION_NOT_ON_PRODUCT: 'في مكان طباعة قديم في الصفحة — حدّث الصفحة من فضلك.',
};

/**
 * The one sentence to show. Only the FIRST error is surfaced — a customer who
 * lowered the quantity below the MOQ does not need to be told four things at
 * once, and the second message is usually a consequence of the first.
 */
export function firstQuoteMessage(errors: QuoteError[]): string | null {
  for (const e of errors) {
    const m = MESSAGES[e];
    if (m) return m;
  }
  return errors.length ? 'في حاجة مش مظبوطة في الاختيارات.' : null;
}

export function quoteMessage(error: QuoteError): string {
  return MESSAGES[error] ?? 'في حاجة مش مظبوطة في الاختيارات.';
}
