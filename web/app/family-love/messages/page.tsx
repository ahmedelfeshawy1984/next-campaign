'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
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

interface MessageRow {
  id: string;
  body: string;
  created_at: string;
  sender_member_id: string | null;
  sender_child_id: string | null;
  recipient_member_id: string | null;
}

export default function FamilyLoveMessagesPage() {
  const router = useRouter();
  const [ready, setReady] = useState(false);
  const [myAccountId, setMyAccountId] = useState<string | null>(null);
  const [members, setMembers] = useState<FamilyMember[]>([]);
  const [messages, setMessages] = useState<MessageRow[]>([]);
  const [recipientId, setRecipientId] = useState('');
  const [body, setBody] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const memberLabel = useCallback(
    (id: string | null) => {
      if (!id) return 'الطفل';
      const m = members.find((x) => x.id === id);
      if (!m) return '—';
      return m.display_name || RELATION_LABELS[m.relation_type];
    },
    [members]
  );

  const load = useCallback(async () => {
    const sb = familyLoveSupabase();
    const [{ data: accountId }, { data: memberRows }, { data: messageRows }] = await Promise.all([
      sb.rpc('fl_my_account_id'),
      sb.from('family_members').select('*').order('created_at'),
      sb.from('messages').select('*').order('created_at', { ascending: false }).limit(50),
    ]);
    setMyAccountId((accountId as string | null) ?? null);
    setMembers((memberRows ?? []) as FamilyMember[]);
    setMessages((messageRows ?? []) as MessageRow[]);
  }, []);

  useEffect(() => {
    if (!hasStoredSession() || currentDeviceKind() !== 'parent') {
      router.replace('/family-love/login');
      return;
    }
    load().finally(() => setReady(true));
  }, [router, load]);

  const myMember = members.find((m) => m.account_id === myAccountId);
  const others = members.filter((m) => m.account_id !== myAccountId);

  async function send(event: React.FormEvent) {
    event.preventDefault();
    if (!body.trim() || !recipientId || !myMember) return;
    setBusy(true);
    setError(null);
    try {
      const { error: insertError } = await familyLoveSupabase().from('messages').insert({
        family_circle_id: myMember.family_circle_id,
        sender_member_id: myMember.id,
        recipient_member_id: recipientId,
        body: body.trim(),
      });
      if (insertError) throw insertError;
      setBody('');
      await load();
    } catch {
      setError('الرسالة معرفتش تتبعت، جرب تاني.');
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

      <h1 style={{ fontSize: '1.1rem', marginBlock: '0 12px' }}>💬 الرسايل</h1>

      {others.length === 0 ? (
        <div className="fl__card fl__center">
          <p className="fl__muted">لسه معندكش أفراد عيلة تانيين تبعتلهم رسالة.</p>
        </div>
      ) : (
        <form onSubmit={send} className="fl__card">
          <label htmlFor="fl-msg-to">لمين؟</label>
          <select id="fl-msg-to" className="fl__input" value={recipientId} onChange={(e) => setRecipientId(e.target.value)}>
            <option value="">اختار...</option>
            {others.map((m) => (
              <option key={m.id} value={m.id}>
                {m.display_name || RELATION_LABELS[m.relation_type]} ({RELATION_LABELS[m.relation_type]})
              </option>
            ))}
          </select>
          <label htmlFor="fl-msg-body">الرسالة</label>
          <textarea
            id="fl-msg-body"
            className="fl__input"
            rows={3}
            value={body}
            onChange={(e) => setBody(e.target.value)}
          />
          {error && <p className="fl__error">{error}</p>}
          <button type="submit" className="btn btn--brand" disabled={busy} style={{ inlineSize: '100%', marginBlockStart: 10 }}>
            ابعت
          </button>
        </form>
      )}

      <div className="fl__card">
        {messages.length === 0 && <p className="fl__muted">لسه مفيش رسايل.</p>}
        <ul className="fl__list">
          {messages.map((m) => (
            <li key={m.id}>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: '0.8rem', color: 'var(--ink-soft)' }}>
                  {memberLabel(m.sender_member_id)} ← {memberLabel(m.recipient_member_id)}
                </div>
                <div>{m.body}</div>
              </div>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
