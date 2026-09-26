import { NextResponse } from 'next/server';
import { isEgMobile, normalizePhone } from '@/lib/phone.js';
import { getOtpProvider } from '@/lib/family-love/otpProvider';

export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: 'BAD_REQUEST' }, { status: 400 });
  }

  const rawPhone = (body as { phone?: unknown })?.phone;
  const phone = normalizePhone(typeof rawPhone === 'string' ? rawPhone : '');
  if (!isEgMobile(phone)) {
    return NextResponse.json({ error: 'BAD_PHONE' }, { status: 400 });
  }

  try {
    await getOtpProvider().sendCode(phone);
  } catch {
    return NextResponse.json({ error: 'OTP_SEND_FAILED' }, { status: 502 });
  }

  return NextResponse.json({ ok: true });
}
