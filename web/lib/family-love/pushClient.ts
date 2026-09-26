'use client';

// تفعيل Web Push من المتصفح — بتتنادى بضغطة زرار المستخدم (مش تلقائي)، لأن
// على آيفون Notification.requestPermission() لازم يبقى جوه user gesture،
// وعمومًا أفضل تجربة إنك متطلبش صلاحية غير لما حد يطلبها فعلاً.
import { getAccessToken } from './session';

function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const raw = atob(base64);
  return Uint8Array.from([...raw].map((c) => c.charCodeAt(0)));
}

export type PushSetupResult = 'subscribed' | 'unsupported' | 'denied' | 'not_installed' | 'error';

/**
 * لازم يبقى عندنا service worker مسجّل الأول (ServiceWorker.tsx). على iOS، ده
 * مبيشتغلش غير لو التطبيق اتضاف فعلاً للشاشة الرئيسية وبيشتغل standalone —
 * الكود هنا بيتأكد من كده قبل ما يطلب الصلاحية.
 */
export async function setupPushNotifications(vapidPublicKey: string): Promise<PushSetupResult> {
  if (!('serviceWorker' in navigator) || !('PushManager' in window)) return 'unsupported';

  const isStandalone =
    window.matchMedia('(display-mode: standalone)').matches ||
    (navigator as { standalone?: boolean }).standalone === true;
  const isIOS = /iphone|ipad|ipod/i.test(navigator.userAgent);
  if (isIOS && !isStandalone) return 'not_installed';

  const permission = await Notification.requestPermission();
  if (permission !== 'granted') return 'denied';

  try {
    const registration = await navigator.serviceWorker.ready;
    let subscription = await registration.pushManager.getSubscription();
    if (!subscription) {
      subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(vapidPublicKey) as BufferSource,
      });
    }

    const token = await getAccessToken();
    const json = subscription.toJSON() as { endpoint?: string; keys?: { p256dh?: string; auth?: string } };
    await fetch('/api/family-love/push/subscribe', {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
      body: JSON.stringify({ endpoint: json.endpoint, keys: json.keys }),
    });

    return 'subscribed';
  } catch {
    return 'error';
  }
}
