// استبدال {{placeholder}} في نصوص message_templates. عمدًا في TypeScript مش
// SQL — تعديل صياغة الرسائل بعدين محتاج نشرة كود بس، مش migration.

export function renderTemplate(template: string, vars: Record<string, string>): string {
  return template.replace(/\{\{(\w+)\}\}/g, (_match, key: string) => vars[key] ?? '');
}

export function mapsLink(lat: number, lng: number): string {
  return `https://maps.google.com/?q=${lat},${lng}`;
}
