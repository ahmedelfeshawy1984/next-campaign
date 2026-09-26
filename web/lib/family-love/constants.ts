// عمر توكن الوصول (access token) - قصير عمدًا لأن التجديد صامت ورخيص
// (session/refresh)، فمفيش داعي لعمر طويل يزود مخاطر تسريبه.
export const ACCESS_TOKEN_TTL_SECONDS = 15 * 60;
