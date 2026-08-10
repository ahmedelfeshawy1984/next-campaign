'use client';

import { useEffect, useState } from 'react';
import { browserSupabase } from '@/lib/supabase-browser';
import { adminErrorMessage, currentAdmin } from '@/lib/admin';
import { prettyPhone } from '@/lib/phone.js';

interface Staff {
  id: string;
  full_name: string;
  phone: string;
  role: string;
  is_active: boolean;
}

export default function AdminStaff() {
  const sb = browserSupabase();
  const [rows, setRows] = useState<Staff[]>([]);
  const [me, setMe] = useState<string | null>(null);
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null);

  function load() {
    sb.rpc('admin_staff').then(({ data }) => setRows((data as Staff[]) ?? []));
    currentAdmin().then((s) => setMe(s?.userId ?? null));
  }
  useEffect(load, []);

  async function call(fn: string, args: Record<string, unknown>, ok: string) {
    setMsg(null);
    const { error } = await sb.rpc(fn, args);
    if (error) setMsg({ text: adminErrorMessage(error.message), bad: true });
    else setMsg({ text: ok });
    load();
  }

  return (
    <>
      <div className="row">
        <h1 style={{ margin: 0 }}>المستخدمين</h1>
        <span className="spacer" />
        <button
          type="button"
          className="btn btn--brand btn--sm"
          onClick={() => {
            const phone = window.prompt('الموبايل؟');
            if (!phone) return;
            const name = window.prompt('الاسم؟');
            if (!name) return;
            const pass = window.prompt('كلمة السر؟ (٦ حروف على الأقل)');
            if (!pass) return;
            const isManager = window.confirm('يبقى مدير بصلاحيات كاملة؟ (إلغاء = موظف عادي)');
            call(
              'admin_create_user',
              {
                p_phone: phone,
                p_full_name: name,
                p_role: isManager ? 'manager' : 'customer',
                p_password: pass,
              },
              'اتضاف'
            );
          }}
        >
          + مستخدم
        </button>
      </div>

      {msg ? <p className={msg.bad ? 'notice notice--warn' : 'notice'}>{msg.text}</p> : null}

      <p className="cfg__hint">
        ⚠ لو لسه بتستخدم كلمة السر الافتراضية اللي جت مع التثبيت، غيّرها دلوقتي — هي
        مكتوبة في ملفات المشروع وأي حد يقراها يعرفها.
      </p>

      <div className="admin__scroll">
        <table className="admin__table">
          <thead>
            <tr>
              <th>الاسم</th>
              <th>الموبايل</th>
              <th>الصلاحية</th>
              <th>الحالة</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.id}>
                <td>
                  {r.full_name}
                  {r.id === me ? <span className="cfg__hint"> (انت)</span> : null}
                </td>
                <td className="num" dir="ltr">
                  {prettyPhone(r.phone)}
                </td>
                <td>{r.role === 'manager' ? 'مدير' : 'موظف'}</td>
                <td>{r.is_active ? 'شغّال' : 'موقوف'}</td>
                <td>
                  <button
                    type="button"
                    className="btn btn--ghost btn--sm"
                    onClick={() => {
                      const pass = window.prompt('كلمة السر الجديدة؟');
                      if (pass) call('admin_set_password', { p_id: r.id, p_password: pass }, 'اتغيّرت');
                    }}
                  >
                    غيّر كلمة السر
                  </button>{' '}
                  {r.id !== me ? (
                    <button
                      type="button"
                      className="btn btn--ghost btn--sm"
                      onClick={() =>
                        call('admin_set_active', { p_id: r.id, p_active: !r.is_active }, 'اتغيّر')
                      }
                    >
                      {r.is_active ? 'أوقف' : 'شغّل'}
                    </button>
                  ) : null}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
