-- ============================================================================
--  الهوية — اللوجو وصورة الواجهة
--
--  ⚠  Sorts AFTER 20260810100006_rls.sql. The table-level `grant select on
--     public.site_settings` already covers every column, including these, so
--     no new grants are needed — but the file still sorts late by the rule.
--
--  WHY THIS IS A MIGRATION AND NOT A CODE EDIT
--
--  The logo, the shop name and the picture on the front page were all in source
--  files: a coloured square in the header component and a string constant. The
--  owner asked how to change them, which is the question that proves the design
--  was wrong. A shop's own name and mark are the FIRST things it wants to
--  change and the LAST things it should need a developer for.
--
--  They live in site_settings now, next to the phone number and the VAT rate,
--  and the admin panel edits them like anything else.
-- ============================================================================

alter table public.site_settings
  add column if not exists logo_url text,
  add column if not exists hero_url text,
  -- Alt text is not decoration. The logo is the first thing a screen reader
  -- meets, and "image" is not a shop name.
  add column if not exists hero_alt_ar text;

comment on column public.site_settings.logo_url is
  'شعار الموقع في الهيدر. فاضي = يظهر المربع الملون بلون الهوية.';
comment on column public.site_settings.hero_url is
  'صورة كبيرة في أول الصفحة الرئيسية. فاضي = الواجهة تفضل نصوص بس.';
