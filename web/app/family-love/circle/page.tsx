'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { hasStoredSession, currentDeviceKind } from '@/lib/family-love/session';
import { familyLoveSupabase } from '@/lib/family-love/supabaseBrowser';
import { qrCodeUrl } from '@/lib/family-love/qr';
import type { FamilyMember, RelationType } from '@/lib/family-love/types';

const RELATION_LABELS: Record<RelationType, string> = {
  mother: 'أم',
  father: 'أب',
  spouse: 'زوج/زوجة',
  grandmother: 'جدة',
  grandfather: 'جد',
  sibling: 'أخ/أخت',
  other: 'فرد من العيلة',
};

export default function FamilyLoveCirclePage() {
  const router = useRouter();
  const [ready, setReady] = useState(false);
  const [members, setMembers] = useState<FamilyMember[]>([]);
  const [relation, setRelation] = useState<RelationType>('spouse');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [invite, setInvite] = useState<{ code: string; link: string } | null>(null);

  const load = useCallback(async () => {
    const { data } = await familyLoveSupabase().from('family_members').select('*').order('created_at');
    setMembers((data ?? []) as FamilyMember[]);
  }, []);

  useEffect(() => {
    if (!hasStoredSession() || currentDeviceKind() !== 'parent') {
      router.replace('/family-love/login');
      return;
    }
    load().finally(() => setReady(true));
  }, [router, load]);

  async function createInvite(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    setInvite(null);
    try {
      const { data, error: rpcError } = await familyLoveSupabase()
        .rpc('fl_create_member_invite', { p_relation_type: relation })
        .single<{ code: string }>();
      if (rpcError || !data) throw rpcError;
      setInvite({ code: data.code, link: `${window.location.origin}/family-love/join?code=${data.code}` });
    } catch {
      setError('معرفناش ننشئ دعوة دلوقتي، جرب تاني.');
    } finally {
      setBusy(false);
    }
  }

  if (!ready) return null;

  return (
    <div className="fl__shell">
      <div className="fl__bar">
        <Link href="/family-love/home" className="fl__brand" style={{ textDecoration: 'none' }}>
          عائلتي
        </Link>
      </div>

      <h1 style={{ fontSize: '1.1rem', marginBlock: '0 12px' }}>👪 أفراد العيلة</h1>

      <div className="fl__card">
        <ul className="fl__list">
          {members.map((member) => (
            <li key={member.id}>
              <div>
                <div style={{ fontWeight: 700 }}>{member.display_name || RELATION_LABELS[member.relation_type]}</div>
                <div className="fl__muted">
                  {RELATION_LABELS[member.relation_type]}
                  {member.is_owner ? ' — صاحب/ة الحساب' : ''}
                </div>
              </div>
            </li>
          ))}
        </ul>
      </div>

      <form onSubmit={createInvite} className="fl__card">
        <h2 style={{ marginBlock: '0 8px', fontSize: '1rem' }}>دعوة فرد جديد</h2>
        <label htmlFor="fl-relation">صلة القرابة</label>
        <select
          id="fl-relation"
          className="fl__input"
          value={relation}
          onChange={(e) => setRelation(e.target.value as RelationType)}
        >
          {(Object.keys(RELATION_LABELS) as RelationType[]).map((key) => (
            <option key={key} value={key}>
              {RELATION_LABELS[key]}
            </option>
          ))}
        </select>
        {error && <p className="fl__error">{error}</p>}
        <button type="submit" className="btn btn--brand" disabled={busy} style={{ inlineSize: '100%', marginBlockStart: 10 }}>
          إنشاء رابط دعوة
        </button>
      </form>

      {invite && (
        <div className="fl__card">
          <p className="fl__muted" style={{ marginBlock: 0 }}>
            كود الدعوة (صالح ٢٤ ساعة):
          </p>
          <p style={{ fontSize: '1.4rem', fontWeight: 800, letterSpacing: '0.2em', margin: '4px 0' }}>{invite.code}</p>
          {/* eslint-disable-next-line @next/next/no-img-element -- صورة QR من خدمة خارجية */}
          <img src={qrCodeUrl(invite.link)} alt="كود QR للانضمام للعيلة" width={160} height={160} />
          <p className="fl__muted" style={{ wordBreak: 'break-all' }}>{invite.link}</p>
        </div>
      )}
    </div>
  );
}
