'use client';

import { useRef, useState } from 'react';
import {
  ALLOWED_EXT,
  dpiAt,
  dpiWarning,
  rejectionReason,
  uploadArtwork,
  type UploadedAsset,
} from '@/lib/uploads';

// رفع اللوجو.
//
// Two things this component refuses to do, both deliberate:
//
//   * it does not try to rasterise .ai / .eps / .pdf for a thumbnail. Every
//     browser-side attempt fails precisely on the files that matter, and a
//     broken preview reads as a rejected file. Vector uploads get a chip with
//     the filename and a promise of a real proof.
//   * it does not render an uploaded SVG inline. That is an XSS vector; only
//     raster files reach an <img>, and only through a blob URL.

interface Props {
  assets: UploadedAsset[];
  onChange: (assets: UploadedAsset[]) => void;
  /** Printed width in mm at the chosen position, for the DPI warning. */
  areaWidthMm?: number | null;
  needsVector?: boolean;
  max?: number;
}

export default function LogoUploader({
  assets,
  onChange,
  areaWidthMm,
  needsVector,
  max = 3,
}: Props) {
  const input = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleFiles(files: FileList | null) {
    if (!files?.length) return;
    setError(null);

    const room = max - assets.length;
    if (room <= 0) {
      setError(`أقصى ${max} ملفات للمنتج الواحد`);
      return;
    }

    setBusy(true);
    try {
      const next: UploadedAsset[] = [];
      for (const file of Array.from(files).slice(0, room)) {
        // Checked here BEFORE the network call, so a 30 MB file is refused
        // instantly instead of after a two-minute upload on mobile data.
        const reason = rejectionReason(file);
        if (reason) {
          setError(reason);
          continue;
        }
        next.push(await uploadArtwork(file));
      }
      if (next.length) onChange([...assets, ...next]);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'مشكلة في رفع الملف');
    } finally {
      setBusy(false);
      if (input.current) input.current.value = '';
    }
  }

  return (
    <div>
      <input
        ref={input}
        type="file"
        multiple
        className="sr-only"
        accept={ALLOWED_EXT.map((e) => `.${e}`).join(',')}
        onChange={(e) => handleFiles(e.target.files)}
      />

      <button
        type="button"
        className="cfg__drop"
        disabled={busy || assets.length >= max}
        onClick={() => input.current?.click()}
      >
        {busy ? 'جاري الرفع…' : assets.length ? 'ضيف ملف تاني' : 'ارفع اللوجو أو التصميم'}
        <span className="cfg__hint">
          {ALLOWED_EXT.join('، ')} — لحد ٢٠ ميجا
        </span>
      </button>

      {needsVector ? (
        <p className="cfg__hint" style={{ marginBlockStart: 8 }}>
          الطريقة اللي اخترتها بتشتغل أحسن مع ملف vector (AI أو EPS أو PDF). لو
          معندكش، ارفع أي صورة واضحة وإحنا نعملهولك.
        </p>
      ) : null}

      {error ? (
        <p className="notice notice--warn" style={{ marginBlockStart: 10 }}>
          {error}
        </p>
      ) : null}

      {assets.length ? (
        <ul className="cfg__files">
          {assets.map((a) => {
            const dpi = dpiAt(a.width, areaWidthMm);
            const warn = dpiWarning(dpi);
            return (
              <li key={a.path} className="cfg__file">
                {a.previewUrl ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={a.previewUrl} alt="" className="cfg__file-thumb" />
                ) : (
                  <span className="cfg__file-ext">{a.ext.toUpperCase()}</span>
                )}
                <span className="cfg__file-body">
                  <strong>{a.name}</strong>
                  <span className="cfg__hint num" dir="ltr">
                    {(a.bytes / 1024).toFixed(0)} KB
                    {a.width ? ` · ${a.width}×${a.height}` : ''}
                    {dpi ? ` · ${dpi} dpi` : ''}
                  </span>
                  {warn ? <span className="cfg__file-warn">{warn}</span> : null}
                  {!a.previewUrl ? (
                    <span className="cfg__hint">
                      هنراجع الملف ونبعتلك معاينة قبل التنفيذ
                    </span>
                  ) : null}
                </span>
                <button
                  type="button"
                  className="cfg__file-x"
                  aria-label={`شيل ${a.name}`}
                  onClick={() => onChange(assets.filter((x) => x.path !== a.path))}
                >
                  ✕
                </button>
              </li>
            );
          })}
        </ul>
      ) : null}
    </div>
  );
}
