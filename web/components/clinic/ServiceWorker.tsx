'use client';

import { useEffect } from 'react';

// تسجيل السيرفس ووركر — للعيادة بس.
//
// THE SCOPE IS THE WHOLE POINT. `/clinic/` and nothing above it.
//
// A service worker registered at the root would take over the shop as well,
// and the shop is a server-rendered catalogue whose entire reason for existing
// — see docs/القرارات.md — is that Google and WhatsApp can read it and that a
// price change is live immediately. A cache-first worker sitting in front of
// that would serve yesterday's prices to a customer and a stale page to a
// crawler.
//
// So the file is served from /clinic-sw.js with an explicit scope, and the
// shop never learns it exists.

export default function ServiceWorker() {
  useEffect(() => {
    if (!('serviceWorker' in navigator)) return;
    // Registering over http://localhost is allowed; over plain http on a LAN
    // address it is not, and the browser's error is unhelpful. The clinic
    // laptop runs this over https in production.
    navigator.serviceWorker
      .register('/clinic-sw.js', { scope: '/clinic/' })
      .catch(() => {
        /* No worker means no offline app SHELL. The local database and the
           outbox are untouched by this, so writing and printing still work for
           as long as the tab stays open. Not worth an error in the doctor's
           face. */
      });
  }, []);

  return null;
}
