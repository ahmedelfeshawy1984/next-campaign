'use client';

// لوجو العيادة — بيتصغّر في المتصفح قبل ما يتحفظ.
//
// The logo is stored as a data: URI on the settings row rather than in a
// storage bucket, so that it travels onto the device with the rest of the
// settings and the letterhead still prints when the clinic's internet is down.
// See the note in 20260812100008_clinic_branding.sql.
//
// That only works if the file is small. A photograph of a printed logo off a
// phone is three to eight megabytes, which as base64 would be a third bigger
// again — downloaded by every device on every settings read, and past the
// column's 400 kB cap anyway.
//
// So the browser resizes it here, before it is ever sent. Canvas, no library.

/** Long edge, in pixels. 600 prints crisply at the ~25mm a letterhead uses. */
const MAX_EDGE = 600;

export interface LogoResult {
  dataUrl: string;
  /** Approximate stored size, so the screen can show it rather than guess. */
  bytes: number;
  width: number;
  height: number;
}

export async function prepareLogo(file: File): Promise<LogoResult> {
  if (!file.type.startsWith('image/')) throw new Error('LOGO_NOT_IMAGE');
  // Before decoding, not after: a 40 MB file should be refused rather than
  // decoded into browser memory first.
  if (file.size > 12 * 1024 * 1024) throw new Error('LOGO_TOO_BIG');

  const bitmap = await createImageBitmap(file).catch(() => {
    throw new Error('LOGO_UNREADABLE');
  });

  const scale = Math.min(1, MAX_EDGE / Math.max(bitmap.width, bitmap.height));
  const width = Math.max(1, Math.round(bitmap.width * scale));
  const height = Math.max(1, Math.round(bitmap.height * scale));

  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext('2d');
  if (!ctx) throw new Error('LOGO_UNREADABLE');

  // A logo is usually a dark mark on transparency or white. Painting white
  // underneath keeps a transparent PNG from turning into a black block when
  // the printer flattens it — which is what it does.
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, width, height);
  ctx.drawImage(bitmap, 0, 0, width, height);
  bitmap.close?.();

  // PNG first: a logo is flat colour and line art, where PNG is both smaller
  // and sharper than JPEG. Fall back to JPEG only if the PNG is too big —
  // which happens with a photographed logo rather than an exported one.
  let dataUrl = canvas.toDataURL('image/png');
  if (dataUrl.length > 380_000) dataUrl = canvas.toDataURL('image/jpeg', 0.85);
  if (dataUrl.length > 380_000) dataUrl = canvas.toDataURL('image/jpeg', 0.6);
  if (dataUrl.length > 400_000) throw new Error('LOGO_TOO_BIG');

  return { dataUrl, bytes: dataUrl.length, width, height };
}

export const LOGO_ERRORS: Record<string, string> = {
  LOGO_NOT_IMAGE: 'الملف ده مش صورة.',
  LOGO_TOO_BIG: 'الصورة كبيرة أوي — جرّب صورة أصغر أو لوجو مقصوص.',
  LOGO_UNREADABLE: 'مش قادرين نقرا الصورة دي.',
};
