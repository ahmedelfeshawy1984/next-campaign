// URL-as-state.
//
// Carried over from BALL STORE's readFilters/filterUrl (assets/js/ui.js
// 216-238), and it earns its place twice over here. Every filter click is a
// navigation, so:
//
//   * the state is in the URL, which means a filtered catalogue can be sent on
//     WhatsApp and opens the same for the person who receives it;
//   * the page is server-rendered per combination, so Google indexes
//     "أكواب للشركات" rather than one empty shell;
//   * there is no client-side filter state to disagree with what the server
//     returned.
//
// In the App Router this is `searchParams` in a Server Component — the same
// idea the static site had, now with rendering behind it.

export type SearchParams = Record<string, string | string[] | undefined>;

/** First value only. `?sort=a&sort=b` is a hand-edited URL, not a real state. */
export function param(sp: SearchParams, key: string): string | undefined {
  const v = sp[key];
  const s = Array.isArray(v) ? v[0] : v;
  const trimmed = s?.trim();
  return trimmed ? trimmed : undefined;
}

/**
 * The current URL with some keys changed. A value of `undefined` REMOVES the
 * key, which is what makes "the active filter chip is a remove button" a
 * one-liner at every call site.
 */
export function filterUrl(
  basePath: string,
  current: SearchParams,
  patch: Record<string, string | undefined>
): string {
  const next = new URLSearchParams();

  for (const [k, v] of Object.entries(current)) {
    const s = Array.isArray(v) ? v[0] : v;
    if (s) next.set(k, s);
  }
  for (const [k, v] of Object.entries(patch)) {
    if (v === undefined || v === '') next.delete(k);
    else next.set(k, v);
  }

  const qs = next.toString();
  return qs ? `${basePath}?${qs}` : basePath;
}
