-- ============================================================================
--  التخزين — دلوان: صور المنتجات (عام) وملفات العملاء (خاص)
-- ============================================================================

-- صور المنتجات. Public read: it is a shop window, and a signed URL per card in
-- a scrolling grid is a round trip per card.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('product-media', 'product-media', true, 5242880,
        array['image/jpeg','image/png','image/webp','image/avif','image/svg+xml'])
on conflict (id) do nothing;

-- ملفات العملاء — لوجوهات وتصميمات.
--
-- PRIVATE, and that is not a default — it is a decision. A customer's
-- unreleased logo is their property, not a shop window. The admin reads it
-- through a signed URL.
--
-- allowed_mime_types IS DELIBERATELY NULL. Browsers report .ai as
-- application/pdf or as an empty string, .cdr as application/octet-stream, and
-- Safari sometimes sends ''. A strict mime list here rejects genuine artwork
-- and the customer blames the site. The real gate is an EXTENSION + size check
-- in the browser and again in register_upload() (20260810100008).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('customer-artwork', 'customer-artwork', false, 20971520, null)
on conflict (id) do nothing;

-- ---------------------------------------------------------- product media ----

drop policy if exists product_media_read on storage.objects;
create policy product_media_read on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'product-media');

drop policy if exists product_media_write on storage.objects;
create policy product_media_write on storage.objects
  for all to authenticated
  using (bucket_id = 'product-media' and public.is_manager())
  with check (bucket_id = 'product-media' and public.is_manager());

-- -------------------------------------------------------- customer artwork ----

-- The path is customer-artwork/<auth.uid()>/<uuid>.<ext>, and the first folder
-- segment IS the authorisation. Same shape as the avatars policy in the
-- egy-league project, with two deliberate divergences:
--
--   * no public read — see above;
--   * no customer DELETE after submission. The file is evidence of what was
--     agreed, and a customer who deletes their artwork mid-job leaves the
--     workshop holding a job sheet that points at nothing.
--
-- Note this policy alone is not enough: create_order_request() must ALSO
-- verify that each submitted path's first segment equals the caller's uid
-- before inserting order_line_assets. Without that check, anyone can attach
-- anyone else's artwork to their own order. It is the single easiest thing in
-- this system to forget, so the harness asserts it.
drop policy if exists artwork_insert on storage.objects;
create policy artwork_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'customer-artwork'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists artwork_update on storage.objects;
create policy artwork_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'customer-artwork'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- The uploader needs to read back what it just wrote to show a thumbnail.
drop policy if exists artwork_read_own on storage.objects;
create policy artwork_read_own on storage.objects
  for select to authenticated
  using (
    bucket_id = 'customer-artwork'
    and ((storage.foldername(name))[1] = auth.uid()::text or public.is_manager())
  );

drop policy if exists artwork_manager_delete on storage.objects;
create policy artwork_manager_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'customer-artwork' and public.is_manager());
