// استخراج جلسة الجهاز من هيدر Authorization لمسار API — مسارات زي
// push/subscribe محتاجة تتأكد مين اللي بيكلمها قبل ما تكتب بمفتاح service
// role (اللي بيتخطى RLS بالكامل).
import type { FlJwtPayload } from './jwt';
import { verifyFlJwt } from './jwt';
import { familyLoveEnv } from './env';

export function deviceSessionFromRequest(request: Request): FlJwtPayload | null {
  const header = request.headers.get('authorization');
  if (!header?.startsWith('Bearer ')) return null;
  const token = header.slice('Bearer '.length).trim();
  if (!token) return null;
  return verifyFlJwt(token, familyLoveEnv.jwtSecret);
}
