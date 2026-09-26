'use client';

import { useEffect, useState, use as usePromise } from 'react';
import { useRouter } from 'next/navigation';
import { hasStoredSession, currentDeviceKind } from '@/lib/family-love/session';
import { familyLoveSupabase } from '@/lib/family-love/supabaseBrowser';
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

export default function EditFamilyMemberPage({ params }: { params: Promise<{ memberId: string }> }) {
  const { memberId } = usePromise(params);
  const router = useRouter();
  const [ready, setReady] = useState(false);
  const [member, setMember] = useState<FamilyMember | null>(null);
  const [displayName, setDisplayName] = useState('');
  const [relationType, setRelationType] = useState<RelationType>('other');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!hasStoredSession() || currentDeviceKind() !== 'parent') {
      router.replace('/family-love/login');
      return;
    }
    (async () => {
      const { data } = await familyLoveSupabase().from('family_members').select('*').eq('id', memberId).maybeSingle<FamilyMember>();
      if (data) {
        setMember(data);
        setDisplayName(data.display_name ?? '');
        setRelationType(data.relation_type);
      }
      setReady(true);
    })();
  }, [router, memberId]);

  async function save(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const { error: updateError } = await familyLoveSupabase()
        .from('family_members')
        .update({ display_name: displayName.trim() || null, relation_type: relationType })
        .eq('id', memberId);
      if (updateError) throw updateError;
      router.replace('/family-love/circle');
    } catch {
      setError('حصلت مشكلة في الحفظ، جرب تاني.');
    } finally {
      setBusy(false);
    }
  }

  if (!ready) return null;
  if (!member) {
    return (
      <div className="fl__shell">
        <div className="fl__card fl__center">
          <p className="fl__muted">الفرد ده مش موجود.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="fl__shell">
      <div className="fl__bar">
        <span className="fl__brand">تعديل بيانات فرد العيلة</span>
      </div>

      <form onSubmit={save} className="fl__card">
        <label htmlFor="fl-member-name">الاسم</label>
        <input
          id="fl-member-name"
          className="fl__input"
          value={displayName}
          onChange={(e) => setDisplayName(e.target.value)}
          placeholder={RELATION_LABELS[relationType]}
        />

        <label htmlFor="fl-member-relation">صلة القرابة</label>
        <select
          id="fl-member-relation"
          className="fl__input"
          value={relationType}
          onChange={(e) => setRelationType(e.target.value as RelationType)}
          disabled={member.is_owner}
        >
          {(Object.keys(RELATION_LABELS) as RelationType[]).map((key) => (
            <option key={key} value={key}>
              {RELATION_LABELS[key]}
            </option>
          ))}
        </select>
        {member.is_owner && <p className="fl__muted">دي صلة قرابتك انت — بتتحدد من غيرك مش من نفسك.</p>}

        {error && <p className="fl__error">{error}</p>}
        <button type="submit" className="btn btn--brand" disabled={busy} style={{ inlineSize: '100%', marginBlockStart: 12 }}>
          {busy ? 'جاري الحفظ...' : 'احفظ'}
        </button>
      </form>
    </div>
  );
}
