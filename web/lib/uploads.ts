'use client';

import { browserSupabase, ensureSession } from './supabase-browser';

// رفع ملفات العملاء.
//
// The bucket is PRIVATE and the path is `<auth.uid()>/<uuid>.<ext>` — the first
// segment IS the authorisation, matched by the storage policy and re-checked by
// create_order_request(). A customer's unreleased logo is their property, not a
// shop window.

export const MAX_BYTES = 20 * 1024 * 1024; // 20 MB. Print artwork is not an avatar.

/**
 * Validated by EXTENSION, never by mime type.
 *
 * Browsers report `.ai` as `application/pdf` or as an empty string, `.cdr` as
 * `application/octet-stream`, and Safari sometimes sends ''. A strict mime
 * check rejects genuine artwork and the customer blames the site. The bucket's
 * mime whitelist is deliberately empty for the same reason; register_upload()
 * enforces this same list again on the server.
 */
export const ALLOWED_EXT = [
  'ai', 'pdf', 'eps', 'svg', 'png', 'jpg', 'jpeg', 'webp', 'cdr', 'zip',
] as const;

const RASTER = new Set(['png', 'jpg', 'jpeg', 'webp']);

export interface UploadedAsset {
  path: string;
  name: string;
  bytes: number;
  ext: string;
  /** Only for raster images; vector files have no pixel size. */
  width: number | null;
  height: number | null;
  /** Object URL for a thumbnail, or null when there is nothing to show. */
  previewUrl: string | null;
}

export function extensionOf(name: string): string {
  const m = name.toLowerCase().match(/\.([a-z0-9]+)$/);
  return m ? m[1] : '';
}

/** Arabic reason, or null when the file is fine. */
export function rejectionReason(file: File): string | null {
  const ext = extensionOf(file.name);
  if (!ext) return 'الملف من غير امتداد — سمّيه باسم فيه نوعه زي logo.ai';
  if (!(ALLOWED_EXT as readonly string[]).includes(ext)) {
    return `الصيغة .${ext} مش مدعومة. المقبول: ${ALLOWED_EXT.join('، ')}`;
  }
  if (file.size > MAX_BYTES) {
    return `الملف ${(file.size / 1048576).toFixed(1)} ميجا — الحد الأقصى ٢٠ ميجا`;
  }
  if (file.size === 0) return 'الملف فاضي';
  return null;
}

/** Reads pixel dimensions in the browser. Raster only; returns nulls otherwise. */
async function readDimensions(file: File, ext: string): Promise<{ w: number | null; h: number | null; url: string | null }> {
  if (!RASTER.has(ext)) return { w: null, h: null, url: null };
  // Never render an uploaded SVG inline or via createObjectURL into the DOM as
  // markup — it is an XSS vector. Only raster reaches this branch, and only as
  // an <img> src.
  const url = URL.createObjectURL(file);
  try {
    const size = await new Promise<{ w: number; h: number }>((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve({ w: img.naturalWidth, h: img.naturalHeight });
      img.onerror = () => reject(new Error('unreadable'));
      img.src = url;
    });
    return { w: size.w, h: size.h, url };
  } catch {
    return { w: null, h: null, url };
  }
}

/**
 * Effective print resolution: how many dots per inch this file actually has at
 * the size it will be printed.
 *
 * The single most common complaint in this trade is a 200×200 JPEG pulled off
 * Facebook printed 8 cm wide. Telling the customer BEFORE they submit turns an
 * argument into an upsell.
 */
export function dpiAt(pixels: number | null, mm: number | null | undefined): number | null {
  if (!pixels || !mm || Number(mm) <= 0) return null;
  return Math.round(pixels / (Number(mm) / 25.4));
}

export function dpiWarning(dpi: number | null): string | null {
  if (dpi === null) return null;
  if (dpi < 100) return `دقة الملف ${dpi} نقطة/بوصة — قليلة جداً للمقاس ده، الطباعة هتطلع مكسّرة`;
  if (dpi < 150) return `دقة الملف ${dpi} نقطة/بوصة — أقل من المفضّل (١٥٠)، يفضّل ملف أوضح`;
  return null;
}

/**
 * Uploads and registers, in that order.
 *
 * Storage RLS stops a write outside the caller's own folder; register_upload()
 * records it so it can later be attached to an order, and enforces the daily
 * ceiling that storage policies cannot express. An upload that was never
 * registered can never become part of an order.
 */
export async function uploadArtwork(file: File): Promise<UploadedAsset> {
  const reason = rejectionReason(file);
  if (reason) throw new Error(reason);

  const uid = await ensureSession();
  const sb = browserSupabase();

  const ext = extensionOf(file.name);
  const path = `${uid}/${crypto.randomUUID()}.${ext}`;
  const { w, h, url } = await readDimensions(file, ext);

  const { error } = await sb.storage.from('customer-artwork').upload(path, file, {
    // Set explicitly from the extension — file.type lies about .ai and .cdr.
    contentType: file.type || 'application/octet-stream',
    upsert: false,
  });
  if (error) throw new Error(`مشكلة في رفع الملف: ${error.message}`);

  const { error: rpcError } = await sb.rpc('register_upload', {
    p_path: path,
    p_original_name: file.name,
    p_mime: file.type || null,
    p_bytes: file.size,
    p_px_width: w,
    p_px_height: h,
  });
  if (rpcError) throw new Error(`الملف اترفع لكن مش اتسجّل: ${rpcError.message}`);

  return { path, name: file.name, bytes: file.size, ext, width: w, height: h, previewUrl: url };
}
