'use client';

import { useEffect } from 'react';

// تسجيل السيرفس ووركر — لـ /family-love/ بس، بنفس منطق العيادة: نطاق صريح
// عشان السيرفس ووركر ميتخطاش لباقي المستودع (الشوب/العيادة).

export default function ServiceWorker() {
  useEffect(() => {
    if (!('serviceWorker' in navigator)) return;
    navigator.serviceWorker
      .register('/family-love-sw.js', { scope: '/family-love/' })
      .catch(() => {
        // مفيش عمل بالخلفية أو تثبيت PWA من غير الووركر ده، لكن الشاشة
        // المفتوحة تفضل شغالة عادي — مش لازم رسالة خطأ تقلق مستخدم.
      });
  }, []);

  return null;
}
