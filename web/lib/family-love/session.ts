'use client';

// إدارة جلسة الجهاز في المتصفح — أب/أم أو طفل، بالظبط نفس الشكل. توكن
// التجديد (refresh) بيتخزن في localStorage، وتوكن الوصول (access) بيفضل في
// الذاكرة بس ويتجدد بصمت قبل ما ينتهي — ده اللي بيحقق "ينزل ويشتغل وخلاص"
// من غير ما يتسجل دخول تاني.

import type { DeviceKind } from './types';

const STORAGE_KEY = 'family-love-session';

interface StoredSession {
  refreshToken: string;
  kind: DeviceKind;
}

interface LiveTokens {
  accessToken: string;
  expiresAt: number; // epoch seconds
}

let live: LiveTokens | null = null;
let refreshing: Promise<string | null> | null = null;

function readStored(): StoredSession | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? (JSON.parse(raw) as StoredSession) : null;
  } catch {
    return null;
  }
}

function writeStored(session: StoredSession): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(session));
  } catch {
    // خصوصية متصفح صارمة أو تخزين ممتلئ — الجلسة تفضل شغالة في نفس التبويب
    // بس مش هتنجو من إعادة تحميل الصفحة، وده مقبول كحد أدنى بدل ما ينهار.
  }
}

export function saveSession(params: {
  refreshToken: string;
  kind: DeviceKind;
  accessToken: string;
  expiresIn: number;
}): void {
  writeStored({ refreshToken: params.refreshToken, kind: params.kind });
  live = { accessToken: params.accessToken, expiresAt: Math.floor(Date.now() / 1000) + params.expiresIn };
}

export function clearSession(): void {
  try {
    localStorage.removeItem(STORAGE_KEY);
  } catch {
    // مفيش حاجة تانية نعملها لو التخزين مرفوض أصلاً.
  }
  live = null;
}

export function hasStoredSession(): boolean {
  return readStored() !== null;
}

export function currentDeviceKind(): DeviceKind | null {
  return readStored()?.kind ?? null;
}

/** بترجع توكن وصول صالح، وتجدده بصمت لو قرب ينتهي أو انتهى فعلاً. null يعني مفيش جلسة خالص. */
export async function getAccessToken(): Promise<string | null> {
  const now = Math.floor(Date.now() / 1000);
  if (live && live.expiresAt - 60 > now) return live.accessToken;
  if (refreshing) return refreshing;

  const stored = readStored();
  if (!stored) return null;

  refreshing = (async () => {
    try {
      const res = await fetch('/api/family-love/session/refresh', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ refreshToken: stored.refreshToken }),
      });
      if (!res.ok) {
        clearSession();
        return null;
      }
      const data = (await res.json()) as {
        accessToken: string;
        expiresIn: number;
        refreshToken?: string;
      };
      live = { accessToken: data.accessToken, expiresAt: Math.floor(Date.now() / 1000) + data.expiresIn };
      if (data.refreshToken) {
        writeStored({ refreshToken: data.refreshToken, kind: stored.kind });
      }
      return live.accessToken;
    } catch {
      return null;
    } finally {
      refreshing = null;
    }
  })();

  return refreshing;
}
