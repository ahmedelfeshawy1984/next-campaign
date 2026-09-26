// مزوّد OTP — قابل للتبديل عن طريق ملف واحد بس. الافتراضي محليًا هو
// "console" (بيطبع الكود في التيرمينال بدل ما يبعت SMS حقيقي)، وفي الإنتاج
// يشتغل Twilio Verify لو المتغيرات متظبطة — قرار مفتوح في الخطة: ممكن
// نستبدله بـ WhatsApp Cloud API أو بوابة SMS محلية من غير ما نلمس أي حاجة
// تانية في الكود.

export interface OtpProvider {
  sendCode(phoneE164Local: string): Promise<void>;
  checkCode(phoneE164Local: string, code: string): Promise<boolean>;
}

/** بيحوّل 01XXXXXXXXX (الشكل القياسي في المشروع) لصيغة +20 اللي Twilio عايزها. */
function toE164Egypt(localPhone: string): string {
  return `+20${localPhone.slice(1)}`;
}

class ConsoleOtpProvider implements OtpProvider {
  private codes = new Map<string, string>();

  async sendCode(phone: string): Promise<void> {
    const code = String(Math.floor(100000 + Math.random() * 900000));
    this.codes.set(phone, code);
    // eslint-disable-next-line no-console -- ده بديل الـ SMS الحقيقي محليًا، مقصود يظهر.
    console.log(`[family-love otp] ${phone} -> ${code}`);
  }

  async checkCode(phone: string, code: string): Promise<boolean> {
    const expected = this.codes.get(phone);
    if (expected && expected === code) {
      this.codes.delete(phone);
      return true;
    }
    return false;
  }
}

class TwilioVerifyProvider implements OtpProvider {
  constructor(
    private accountSid: string,
    private authToken: string,
    private verifySid: string,
    private channel: 'sms' | 'whatsapp' = 'sms'
  ) {}

  private authHeader(): string {
    return 'Basic ' + Buffer.from(`${this.accountSid}:${this.authToken}`).toString('base64');
  }

  async sendCode(phone: string): Promise<void> {
    const res = await fetch(`https://verify.twilio.com/v2/Services/${this.verifySid}/Verifications`, {
      method: 'POST',
      headers: {
        Authorization: this.authHeader(),
        'content-type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({ To: toE164Egypt(phone), Channel: this.channel }),
    });
    if (!res.ok) {
      throw new Error('OTP_SEND_FAILED');
    }
  }

  async checkCode(phone: string, code: string): Promise<boolean> {
    const res = await fetch(`https://verify.twilio.com/v2/Services/${this.verifySid}/VerificationCheck`, {
      method: 'POST',
      headers: {
        Authorization: this.authHeader(),
        'content-type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({ To: toE164Egypt(phone), Code: code }),
    });
    if (!res.ok) return false;
    const data = (await res.json()) as { status?: string };
    return data.status === 'approved';
  }
}

// singleton — عشان console provider يفتكر الكود بين طلب الإرسال وطلب التحقق
// جوه نفس الـ process (كافي لـ npm run dev المحلي).
let cached: OtpProvider | null = null;

export function getOtpProvider(): OtpProvider {
  if (cached) return cached;

  const sid = process.env.FAMILYLOVE_TWILIO_ACCOUNT_SID;
  const token = process.env.FAMILYLOVE_TWILIO_AUTH_TOKEN;
  const verifySid = process.env.FAMILYLOVE_TWILIO_VERIFY_SID;
  const channel = process.env.FAMILYLOVE_OTP_CHANNEL === 'whatsapp' ? 'whatsapp' : 'sms';

  cached =
    sid && token && verifySid
      ? new TwilioVerifyProvider(sid, token, verifySid, channel)
      : new ConsoleOtpProvider();

  return cached;
}
