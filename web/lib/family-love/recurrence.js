// نسخة JS من public.fl_task_occurs_on() في
// supabase/family-love/migrations/0001_helpers.sql — نفس المنطق حرفيًا.
//
// AUTHORED AS .js على قصد، بنفس سبب web/lib/phone.js: tools/schema-check/
// family-love.mjs بيستورد الملف ده بالظبط عشان يتأكد إنه متطابق مع الدالة
// اللي في SQL على نفس مجموعة التواريخ — نسخة .ts هتحتاج build step في
// الهارنس، ولحظة ما الهارنس يعمل نسخته بنفسه بيبطل يفحص اللي الموقع فعليًا
// بيشحنه. JSDoc بيدّي type checking كامل هنا برضه (tsconfig: allowJs + checkJs).

/**
 * @typedef {{kind: 'once', date: string}} RecurrenceOnce
 * @typedef {{kind: 'daily'}} RecurrenceDaily
 * @typedef {{kind: 'weekly', weekdays: number[]}} RecurrenceWeekly
 * @typedef {{kind: 'monthly', day_of_month: number}} RecurrenceMonthly
 * @typedef {RecurrenceOnce | RecurrenceDaily | RecurrenceWeekly | RecurrenceMonthly} RecurrenceRule
 */

/**
 * @param {Date} d
 * @returns {string}
 */
function isoDate(d) {
  return d.toISOString().slice(0, 10);
}

/**
 * بتُستخدم للعرض الفوري (optimistic) في الواجهة بس — القرار النهائي دايمًا
 * من fl_task_occurs_on() في قاعدة البيانات.
 *
 * @param {RecurrenceRule} rule
 * @param {Date} date
 * @returns {boolean}
 */
export function taskOccursOn(rule, date) {
  switch (rule.kind) {
    case 'once':
      return isoDate(date) === rule.date;
    case 'daily':
      return true;
    case 'weekly':
      return rule.weekdays.includes(date.getUTCDay());
    case 'monthly':
      return date.getUTCDate() === rule.day_of_month;
    default:
      return false;
  }
}
