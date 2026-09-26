// توليد صورة QR — عن طريق خدمة عامة بس دلوقتي (v1)، بدل ما نضيف اعتمادية
// جديدة للمستودع علشان زرار واحد. لو لاحقًا احتجنا نولّده محليًا (offline أو
// خصوصية أدق)، الاستبدال محصور في الملف ده بس.
export function qrCodeUrl(data: string, sizePx = 240): string {
  const params = new URLSearchParams({ size: `${sizePx}x${sizePx}`, data });
  return `https://api.qrserver.com/v1/create-qr-code/?${params.toString()}`;
}
