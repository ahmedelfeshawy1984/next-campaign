'use client';

import { useEffect, useState } from 'react';
import { onOutboxChange, flush, startAutoFlush } from '@/lib/clinic/outbox';

// مؤشر الاتصال.
//
// The doctor has to be able to tell, at a glance and without being alarmed,
// whether what they just wrote has left the building. Not because there is
// anything to do about it — the queue drains itself — but because "هل الروشتة
// اتسجّلت؟" is a question that WILL be asked, and an interface that cannot
// answer it invites people to write things twice.
//
// So: quiet when everything is through, factual when it is not, and loud only
// for the one case that needs a human — a record the server has refused and
// will go on refusing.

export default function OfflineBadge() {
  const [online, setOnline] = useState(true);
  const [waiting, setWaiting] = useState(0);
  const [blocked, setBlocked] = useState(0);

  useEffect(() => {
    const sync = () => setOnline(navigator.onLine !== false);
    sync();
    window.addEventListener('online', sync);
    window.addEventListener('offline', sync);

    const stopWatching = onOutboxChange((n, b) => {
      setWaiting(n);
      setBlocked(b);
    });
    const stopFlushing = startAutoFlush();

    return () => {
      window.removeEventListener('online', sync);
      window.removeEventListener('offline', sync);
      stopWatching();
      stopFlushing();
    };
  }, []);

  if (blocked > 0) {
    return (
      <span className="clinic-net clinic-net--bad" title="فيه سجلات السيرفر رفضها">
        <span className="clinic-net__dot" aria-hidden="true" />
        {blocked} محتاجين مراجعة
      </span>
    );
  }

  if (!online) {
    return (
      <span className="clinic-net clinic-net--off">
        <span className="clinic-net__dot" aria-hidden="true" />
        شغّال من غير نت{waiting > 0 ? ` — ${waiting} في الانتظار` : ''}
      </span>
    );
  }

  if (waiting > 0) {
    return (
      <button
        type="button"
        className="clinic-net clinic-net--wait"
        onClick={() => void flush()}
        title="اضغط للرفع دلوقتي"
      >
        <span className="clinic-net__dot" aria-hidden="true" />
        بيترفع — {waiting}
      </button>
    );
  }

  return (
    <span className="clinic-net clinic-net--ok">
      <span className="clinic-net__dot" aria-hidden="true" />
      متصل
    </span>
  );
}
