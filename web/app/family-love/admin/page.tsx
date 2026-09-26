'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { hasStoredSession, currentDeviceKind } from '@/lib/family-love/session';
import { familyLoveSupabase } from '@/lib/family-love/supabaseBrowser';

type Scope = 'all_egypt' | 'governorate' | 'city';

interface CreativeRow {
  id: string;
  image_url: string;
  headline: string | null;
  target_url: string | null;
  is_active: boolean;
  starts_at: string;
  ends_at: string | null;
  ad_targets: Array<{ scope: Scope; governorate: string | null; city: string | null }>;
}

// واجهة إدارة مستقلة تمامًا عن /admin بتاع الشوب — مشروع Supabase مختلف
// خالص، فمفيش داعي (ولا إمكانية فعليًا) لدمجهم. الدخول محصور بـ
// accounts.is_platform_admin = true، وده بيتظبط يدويًا من Supabase dashboard
// دلوقتي — مفيش واجهة لترقية حساب لأدمن عمدًا (فعل نادر، مش يستاهل شاشة).
export default function FamilyLoveAdminPage() {
  const router = useRouter();
  const [ready, setReady] = useState(false);
  const [allowed, setAllowed] = useState(false);
  const [creatives, setCreatives] = useState<CreativeRow[]>([]);
  const [imageUrl, setImageUrl] = useState('');
  const [headline, setHeadline] = useState('');
  const [targetUrl, setTargetUrl] = useState('');
  const [scope, setScope] = useState<Scope>('all_egypt');
  const [area, setArea] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    const { data } = await familyLoveSupabase()
      .from('ad_creatives')
      .select('*, ad_targets(scope, governorate, city)')
      .order('created_at', { ascending: false });
    setCreatives((data ?? []) as CreativeRow[]);
  }, []);

  useEffect(() => {
    if (!hasStoredSession() || currentDeviceKind() !== 'parent') {
      router.replace('/family-love/login');
      return;
    }
    (async () => {
      const { data } = await familyLoveSupabase().rpc('fl_is_platform_admin');
      setAllowed(Boolean(data));
      if (data) await load();
      setReady(true);
    })();
  }, [router, load]);

  async function createCreative(event: React.FormEvent) {
    event.preventDefault();
    if (!imageUrl.trim()) return;
    setBusy(true);
    setError(null);
    try {
      const sb = familyLoveSupabase();
      const { data: creative, error: insertError } = await sb
        .from('ad_creatives')
        .insert({ image_url: imageUrl.trim(), headline: headline.trim() || null, target_url: targetUrl.trim() || null })
        .select('id')
        .single<{ id: string }>();
      if (insertError || !creative) throw insertError;

      const { error: targetError } = await sb.from('ad_targets').insert({
        creative_id: creative.id,
        scope,
        governorate: scope === 'governorate' ? area.trim() : null,
        city: scope === 'city' ? area.trim() : null,
      });
      if (targetError) throw targetError;

      setImageUrl('');
      setHeadline('');
      setTargetUrl('');
      setArea('');
      await load();
    } catch {
      setError('الإعلان معرفش يتحفظ، جرب تاني.');
    } finally {
      setBusy(false);
    }
  }

  async function toggleActive(creative: CreativeRow) {
    await familyLoveSupabase().from('ad_creatives').update({ is_active: !creative.is_active }).eq('id', creative.id);
    await load();
  }

  async function remove(creative: CreativeRow) {
    await familyLoveSupabase().from('ad_creatives').delete().eq('id', creative.id);
    await load();
  }

  if (!ready) return null;

  if (!allowed) {
    return (
      <div className="fl__shell">
        <div className="fl__card fl__center">
          <p className="fl__muted">الشاشة دي للمسؤولين بس.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="fl__shell">
      <div className="fl__bar">
        <span className="fl__brand">إدارة الإعلانات</span>
      </div>

      <form onSubmit={createCreative} className="fl__card">
        <label htmlFor="fl-ad-image">رابط الصورة</label>
        <input id="fl-ad-image" className="fl__input" value={imageUrl} onChange={(e) => setImageUrl(e.target.value)} required />

        <label htmlFor="fl-ad-headline">عنوان (اختياري)</label>
        <input id="fl-ad-headline" className="fl__input" value={headline} onChange={(e) => setHeadline(e.target.value)} />

        <label htmlFor="fl-ad-target">رابط عند الضغط (اختياري)</label>
        <input id="fl-ad-target" className="fl__input" value={targetUrl} onChange={(e) => setTargetUrl(e.target.value)} />

        <label htmlFor="fl-ad-scope">الاستهداف</label>
        <select id="fl-ad-scope" className="fl__input" value={scope} onChange={(e) => setScope(e.target.value as Scope)}>
          <option value="all_egypt">كل مصر</option>
          <option value="governorate">محافظة معينة</option>
          <option value="city">مدينة معينة</option>
        </select>

        {scope !== 'all_egypt' && (
          <input
            className="fl__input"
            placeholder={scope === 'governorate' ? 'اسم المحافظة' : 'اسم المدينة'}
            value={area}
            onChange={(e) => setArea(e.target.value)}
          />
        )}

        {error && <p className="fl__error">{error}</p>}
        <button type="submit" className="btn btn--brand" disabled={busy} style={{ inlineSize: '100%', marginBlockStart: 10 }}>
          إضافة إعلان
        </button>
      </form>

      <div className="fl__card">
        {creatives.length === 0 && <p className="fl__muted">مفيش إعلانات دلوقتي.</p>}
        <ul className="fl__list">
          {creatives.map((c) => (
            <li key={c.id}>
              <div style={{ flex: 1 }}>
                <div style={{ fontWeight: 700 }}>{c.headline || '—'}</div>
                <div className="fl__muted" style={{ wordBreak: 'break-all' }}>{c.image_url}</div>
                <div className="fl__muted">
                  {c.ad_targets.map((t) => (t.scope === 'all_egypt' ? 'كل مصر' : t.governorate || t.city)).join('، ')}
                  {' — '}
                  {c.is_active ? 'شغّال' : 'متوقف'}
                </div>
              </div>
              <button type="button" className="btn btn--ghost btn--sm" onClick={() => toggleActive(c)}>
                {c.is_active ? 'وقّف' : 'شغّل'}
              </button>
              <button type="button" className="btn btn--ghost btn--sm" onClick={() => remove(c)}>
                احذف
              </button>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
