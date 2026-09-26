-- ============================================================================
--  Family Love — دوال أساسية
--
--  مشروع Supabase مستقل تمامًا عن الشوب والعيادة (مفيش مشاركة قاعدة بيانات
--  ولا مصادقة). الدالتين دول نسخة مكررة عمدًا من web/lib/phone.js — نفس
--  المنطق حرفيًا، لكن معزولة هنا لأن قاعدة البيانات دي فعليًا مشروع تاني، مش
--  schema جوه نفس المشروع، فمفيش طريقة تانية لمشاركتهم غير النسخ المتطابق.
--  الحفاظ على التطابق مسؤولية tools/schema-check/family-love.mjs.
-- ============================================================================

create extension if not exists pgcrypto;

create or replace function public.normalize_phone(p_raw text)
returns text
language plpgsql immutable as $$
declare v text;
begin
  if p_raw is null then return null; end if;

  v := translate(p_raw, '٠١٢٣٤٥٦٧٨٩', '0123456789');
  v := translate(v,     '۰۱۲۳۴۵۶۷۸۹', '0123456789');
  v := regexp_replace(v, '[^0-9]', '', 'g');

  if v like '0020%'                   then v := '0' || substr(v, 5); end if;
  if v like '20%'  and length(v) = 12 then v := '0' || substr(v, 3); end if;
  if length(v) = 10 and v like '1%'   then v := '0' || v;            end if;

  return v;
end $$;

create or replace function public.is_eg_mobile(p_raw text)
returns boolean
language sql immutable as $$
  select public.normalize_phone(p_raw) ~ '^01[0125][0-9]{8}$'
$$;

-- ---------------------------------------------------------------------------
--  التكرار: نفس المنطق الموجود في web/lib/family-love/recurrence.ts، ومطابقته
--  مضمونة بنفس طريقة normalize_phone فوق — دالة SQL ودالة TS بيتفحصوا سوا.
-- ---------------------------------------------------------------------------
create or replace function public.fl_task_occurs_on(p_rule jsonb, p_date date)
returns boolean
language sql immutable as $$
  select case p_rule ->> 'kind'
    when 'once'    then (p_rule ->> 'date')::date = p_date
    when 'daily'   then true
    when 'weekly'  then extract(dow from p_date)::int = any (
                          array(select jsonb_array_elements_text(p_rule -> 'weekdays')::int)
                        )
    when 'monthly' then extract(day from p_date)::int = (p_rule ->> 'day_of_month')::int
    else false
  end
$$;
