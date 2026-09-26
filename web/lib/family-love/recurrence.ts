// نسخة TypeScript من public.fl_task_occurs_on() في
// supabase/family-love/migrations/0001_helpers.sql — نفس المنطق حرفيًا،
// مطابقتهم مسؤولية tools/schema-check/family-love.mjs (نفس فكرة
// normalize_phone/phone.js في المستودع).
//
// بتُستخدم للعرض الفوري (optimistic) في الواجهة بس — القرار النهائي دايمًا
// من fl_task_occurs_on() في قاعدة البيانات.

export type RecurrenceRule =
  | { kind: 'once'; date: string } // 'YYYY-MM-DD'
  | { kind: 'daily' }
  | { kind: 'weekly'; weekdays: number[] } // 0=Sunday .. 6=Saturday، زي extract(dow)
  | { kind: 'monthly'; day_of_month: number };

function isoDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

export function taskOccursOn(rule: RecurrenceRule, date: Date): boolean {
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
