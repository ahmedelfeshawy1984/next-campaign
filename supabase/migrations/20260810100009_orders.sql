-- ============================================================================
--  الطلبات — التسجيل وآلة الحالات
--
--  ⚠  Sorts AFTER 20260810100006_rls.sql. Carries its own grants, at the bottom.
--
--  Modelled on the sibling project's buy_requests, and the four rules that made
--  it work carry over unchanged:
--    1. SNAPSHOTS, not joins. Repricing a mug next year must not rewrite an
--       order placed this year.
--    2. A code a human can say on the phone, from a sequence.
--    3. Rate limiting INSIDE the security-definer function. The anon key is in
--       the JavaScript bundle; the app is not the gate.
--    4. Status transitions in a FUNCTION, not an UPDATE policy. A policy can
--       say who may write; only a function can say which move is legal.
--
--  These tables have NO anon grant of any kind. Everything a visitor can do
--  goes through the three RPCs granted at the bottom.
-- ============================================================================

do $$ begin create type public.customer_kind as enum ('company','individual');
exception when duplicate_object then null; end $$;

-- The artwork loop is where every print job actually lives, so it is a status.
-- The owner's daily question is "which jobs are waiting on the customer to
-- approve the proof?" and a boolean cannot answer it.
--
-- The DEPOSIT is deliberately NOT here. It can land at several points in the
-- sequence, and encoding it as a status would force a false ordering; it is a
-- boolean plus an amount on the row.
do $$ begin create type public.order_status as enum (
  'new','contacted','quoted','artwork_review','artwork_approved',
  'in_production','ready','delivered','cancelled');
exception when duplicate_object then null; end $$;

do $$ begin create type public.asset_kind as enum ('logo','reference','proof');
exception when duplicate_object then null; end $$;

create sequence if not exists public.order_code_seq start 1001;

-- ---------------------------------------------------------------------------
--  Uploads, recorded.
--
--  Storage RLS already stops a customer writing outside their own folder. This
--  table is the second half: an upload that was never REGISTERED can never be
--  attached to an order, so a direct write to storage that skips the app buys
--  nothing. It is also where the per-uid ceiling lives, because storage
--  policies cannot count.
-- ---------------------------------------------------------------------------
create table if not exists public.customer_uploads (
  id            uuid primary key default gen_random_uuid(),
  storage_path  text not null unique,
  owner_id      uuid not null,
  original_name text,
  mime          text,
  bytes         bigint,
  px_width      int,
  px_height     int,
  created_at    timestamptz not null default now()
);

create index if not exists customer_uploads_owner_idx
  on public.customer_uploads(owner_id, created_at desc);

-- ---------------------------------------------------------------------------
--  The order.
-- ---------------------------------------------------------------------------
create table if not exists public.order_requests (
  id   uuid primary key default gen_random_uuid(),
  code text not null unique
       default 'NC-' || lpad(nextval('public.order_code_seq')::text, 5, '0'),

  customer_kind public.customer_kind not null,
  contact_name  text not null,
  contact_phone text not null,            -- normalised, 01XXXXXXXXX
  contact_email text,
  company_name  text,
  tax_id        text,                     -- corporates need a tax invoice
  governorate   text,
  area          text,
  address       text,

  needed_by date,                         -- the most useful field after the phone

  -- "أقر بأن لي حق استخدام الشعار". The site receives other companies'
  -- trademarks; this is the one line that says who asked for that.
  ip_confirmed      boolean not null,
  -- SEPARATE from the above on purpose: using a client's logo in your own
  -- portfolio without permission is a different act, and a different consent.
  portfolio_consent boolean not null default false,

  -- Every figure below is the SERVER's, computed by price_quote() at submit
  -- time. client_total is what the browser showed, kept only so a mismatch can
  -- be seen rather than argued about.
  subtotal            numeric(12,2) not null default 0,
  setup_total         numeric(12,2) not null default 0,
  vat_rate_at_request numeric(5,4)  not null default 0,
  vat_amount          numeric(12,2) not null default 0,
  total               numeric(12,2) not null default 0,
  client_total        numeric(12,2),
  price_mismatch      boolean not null default false,

  deposit_amount   numeric(12,2),
  deposit_received boolean not null default false,

  status        public.order_status not null default 'new',
  manager_note  text,
  cancel_reason text,
  customer_note text,
  source        text,
  is_spam       boolean not null default false,

  whatsapp_sent_at timestamptz,
  created_at   timestamptz not null default now(),
  contacted_at timestamptz,
  closed_at    timestamptz
);

create index if not exists order_requests_status_idx on public.order_requests(status, created_at desc);
create index if not exists order_requests_phone_idx  on public.order_requests(contact_phone, created_at desc);
create index if not exists order_requests_needed_idx on public.order_requests(needed_by)
  where status not in ('delivered','cancelled');

-- ---------------------------------------------------------------------------
--  Lines and their children.
--
--  Relational children rather than one payload jsonb, deliberately: the owner
--  will want "how many navy t-shirts did we do in Q1", and the workshop's job
--  sheet has to read the text EXACTLY as the customer typed it. A blob answers
--  neither. The snapshot labels live inside the child rows so renaming an
--  option next year cannot rewrite an old job sheet.
-- ---------------------------------------------------------------------------
create table if not exists public.order_request_lines (
  id         uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.order_requests(id) on delete cascade,
  line_no    int not null,

  product_id uuid references public.products(id) on delete set null,
  product_name_ar  text not null,
  product_slug     text,
  cover_url        text,
  category_name_ar text,

  qty            int not null check (qty >= 1),
  moq_at_request int,

  method_code    text,
  method_name_ar text,
  colors_count   int,
  -- The screen is RGB and the print is Pantone. The swatch is never a promise;
  -- this column is where the promise actually lives.
  pantone_codes  text[],

  setup_fee_at_request  numeric(10,2) not null default 0,
  unit_price_at_request numeric(10,2) not null default 0,
  options_delta         numeric(10,2) not null default 0,
  method_addon          numeric(10,2) not null default 0,
  line_subtotal         numeric(12,2) not null default 0,
  line_total            numeric(12,2) not null default 0,

  is_gift_wrap boolean not null default false,
  gift_message text,
  notes        text,

  unique (request_id, line_no)
);

create table if not exists public.order_line_positions (
  line_id          uuid not null references public.order_request_lines(id) on delete cascade,
  position_id      uuid references public.print_positions(id) on delete set null,
  position_name_ar text not null,
  area_w_mm        numeric(6,1),
  area_h_mm        numeric(6,1),
  setup_fee_applied numeric(10,2) not null default 0,
  primary key (line_id, position_name_ar)
);

create table if not exists public.order_line_options (
  line_id        uuid not null references public.order_request_lines(id) on delete cascade,
  group_code     text not null,
  group_label_ar text not null,
  item_value     text not null,
  item_label_ar  text not null,
  hex            text,
  price_delta    numeric(10,2) not null default 0,
  primary key (line_id, group_code)
);

create table if not exists public.order_line_texts (
  line_id      uuid not null references public.order_request_lines(id) on delete cascade,
  slot         int not null,
  content      text not null,
  font_key     text,
  font_name_ar text,
  color_hex    text,
  pantone_code text,
  primary key (line_id, slot)
);

create table if not exists public.order_line_assets (
  id            uuid primary key default gen_random_uuid(),
  line_id       uuid not null references public.order_request_lines(id) on delete cascade,
  upload_id     uuid references public.customer_uploads(id) on delete set null,
  storage_path  text not null,
  original_name text,
  mime          text,
  bytes         bigint,
  kind          public.asset_kind not null default 'logo',
  uploaded_by   uuid,
  px_width      int,
  px_height     int,
  -- Effective resolution at the printed size, computed in the browser from the
  -- image and the position's area. Stored so the admin sees the same number the
  -- customer was warned about.
  dpi_at_position numeric(6,1),
  created_at    timestamptz not null default now()
);

create index if not exists order_lines_parent_idx  on public.order_request_lines(request_id);
create index if not exists order_assets_parent_idx on public.order_line_assets(line_id);

create table if not exists public.order_request_events (
  id          uuid primary key default gen_random_uuid(),
  request_id  uuid not null references public.order_requests(id) on delete cascade,
  actor_id    uuid,
  from_status public.order_status,
  to_status   public.order_status,
  note        text,
  created_at  timestamptz not null default now()
);

create index if not exists order_events_parent_idx
  on public.order_request_events(request_id, created_at);

create or replace function public.order_status_event()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into public.order_request_events (request_id, to_status, note)
    values (new.id, new.status, 'الطلب وصل');
  elsif old.status is distinct from new.status then
    insert into public.order_request_events (request_id, actor_id, from_status, to_status, note)
    values (new.id, auth.uid(), old.status, new.status,
            coalesce(new.cancel_reason, new.manager_note));
  end if;
  return null;
end $$;

drop trigger if exists order_requests_event on public.order_requests;
create trigger order_requests_event
  after insert or update of status on public.order_requests
  for each row execute function public.order_status_event();

-- ---------------------------------------------------------------------------
--  RLS. No anon grant at all — a visitor never touches these tables directly.
-- ---------------------------------------------------------------------------
alter table public.customer_uploads      enable row level security;
alter table public.order_requests        enable row level security;
alter table public.order_request_lines   enable row level security;
alter table public.order_line_positions  enable row level security;
alter table public.order_line_options    enable row level security;
alter table public.order_line_texts      enable row level security;
alter table public.order_line_assets     enable row level security;
alter table public.order_request_events  enable row level security;

revoke all on
  public.customer_uploads, public.order_requests, public.order_request_lines,
  public.order_line_positions, public.order_line_options, public.order_line_texts,
  public.order_line_assets, public.order_request_events
from anon;

do $$
declare t text;
begin
  foreach t in array array[
    'order_requests','order_request_lines','order_line_positions',
    'order_line_options','order_line_texts','order_line_assets',
    'order_request_events','customer_uploads'
  ] loop
    execute format('drop policy if exists %I_manager on public.%I', t, t);
    execute format(
      'create policy %I_manager on public.%I for all to authenticated
         using (public.is_manager()) with check (public.is_manager())', t, t);
  end loop;
end $$;

-- The one exception: an anonymous uploader may see the rows it registered, so
-- the uploader can show a thumbnail list without a round trip through an RPC.
drop policy if exists customer_uploads_own on public.customer_uploads;
create policy customer_uploads_own on public.customer_uploads
  for select to authenticated using (owner_id = auth.uid());

-- ---------------------------------------------------------------------------
--  THE STATUS COLUMN IS NOT WRITABLE BY ANYONE, INCLUDING A MANAGER.
--
--  The manager policy above says `for all`, which would let the admin panel
--  write `status = 'delivered'` straight onto a brand-new order and skip every
--  transition rule in set_order_status(). A rule you can go around is a
--  suggestion.
--
--  So the privilege is taken at the COLUMN level — the same shape as the
--  profiles.role lock — and set_order_status() reaches it anyway because it is
--  SECURITY DEFINER and runs as the owner. The panel keeps the fields a human
--  genuinely edits by hand.
-- ---------------------------------------------------------------------------
revoke update on public.order_requests from authenticated;
grant update (
  manager_note, deposit_amount, deposit_received, is_spam,
  needed_by, contact_email, area, address
) on public.order_requests to authenticated;

-- ---------------------------------------------------------------------------
--  register_upload()
--
--  Called after the browser has written the object to storage. Validates by
--  EXTENSION, not by mime: browsers report .ai as application/pdf or as an
--  empty string, .cdr as application/octet-stream, and Safari sometimes sends
--  ''. A strict mime check rejects genuine artwork and the customer blames the
--  site.
-- ---------------------------------------------------------------------------
create or replace function public.register_upload(
  p_path text, p_original_name text, p_mime text, p_bytes bigint,
  p_px_width int default null, p_px_height int default null
) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid uuid := auth.uid();
  v_ext text;
  v_recent int;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'NOT_SIGNED_IN' using hint = 'محتاج جلسة قبل رفع الملف';
  end if;

  -- The first path segment IS the authorisation, matching the storage policy.
  if (storage.foldername(p_path))[1] is distinct from v_uid::text then
    raise exception 'ASSET_NOT_YOURS' using hint = 'مسار الملف مش تبع الجلسة دي';
  end if;

  v_ext := lower(regexp_replace(p_path, '^.*\.', ''));
  if v_ext not in ('ai','pdf','eps','svg','png','jpg','jpeg','webp','cdr','zip') then
    raise exception 'FILE_TYPE_NOT_ALLOWED' using hint = 'الصيغة دي مش مدعومة';
  end if;

  if p_bytes is not null and p_bytes > 20971520 then
    raise exception 'FILE_TOO_LARGE' using hint = 'أقصى حجم ٢٠ ميجا';
  end if;

  -- The ceiling storage policies cannot express. Generous for a real customer
  -- with a dozen artworks, useless for a script.
  select count(*) into v_recent
    from public.customer_uploads
   where owner_id = v_uid and created_at > now() - interval '1 day';
  if v_recent >= 40 then
    raise exception 'UPLOAD_LIMIT' using hint = 'رفعت ملفات كتير النهارده';
  end if;

  insert into public.customer_uploads
    (storage_path, owner_id, original_name, mime, bytes, px_width, px_height)
  values (p_path, v_uid, p_original_name, p_mime, p_bytes, p_px_width, p_px_height)
  on conflict (storage_path) do update
    set original_name = excluded.original_name
  returning id into v_id;

  return v_id;
end $$;

-- ---------------------------------------------------------------------------
--  create_order_request()
--
--  The whole submission, in one call. Takes jsonb because the number of lines
--  is not known in advance and a variadic signature would be worse.
--
--  It RECOMPUTES every price with price_quote() and stores its own numbers.
--  Whatever total the browser sends is recorded next to them and ignored.
-- ---------------------------------------------------------------------------
create or replace function public.create_order_request(p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid   uuid := auth.uid();
  v_phone text := public.normalize_phone(p_payload ->> 'contact_phone');
  v_recent int;
  v_global int;
  v_id   uuid;
  v_code text;
  v_line jsonb;
  v_line_id uuid;
  v_no int := 0;
  v_q jsonb;
  v_product record;
  v_method record;
  v_pos jsonb;
  v_opt jsonb;
  v_txt jsonb;
  v_asset text;
  v_upload record;
  v_position_ids uuid[];
  v_option_ids uuid[];
  v_subtotal numeric(12,2) := 0;
  v_setup numeric(12,2) := 0;
  v_vat_rate numeric(5,4);
  v_inclusive boolean;
  v_pre_vat numeric(12,2);
  v_vat numeric(12,2);
  v_client_total numeric(12,2);
begin
  -- ---- who ---------------------------------------------------------------
  if coalesce(p_payload ->> 'contact_name', '') = '' then
    raise exception 'NAME_REQUIRED' using hint = 'الاسم مطلوب';
  end if;
  if not public.is_eg_mobile(v_phone) then
    raise exception 'PHONE_INVALID' using hint = 'رقم موبايل مصري غير صحيح';
  end if;
  if coalesce((p_payload ->> 'ip_confirmed')::boolean, false) is not true then
    raise exception 'IP_NOT_CONFIRMED'
      using hint = 'لازم تأكيد إن لك حق استخدام الشعار';
  end if;
  if jsonb_array_length(coalesce(p_payload -> 'lines', '[]'::jsonb)) = 0 then
    raise exception 'NO_LINES' using hint = 'مفيش منتجات في الطلب';
  end if;

  -- ---- the flood gates ----------------------------------------------------
  -- Inside the function, not in the app: the anon key ships in the bundle, so
  -- anything enforced in JavaScript is enforced nowhere.
  select count(*) into v_recent from public.order_requests
   where contact_phone = v_phone and created_at > now() - interval '1 hour';
  if v_recent >= 3 then
    raise exception 'RATE_LIMITED'
      using hint = 'بعتّ ٣ طلبات في آخر ساعة — كلمنا على واتساب';
  end if;

  select count(*) into v_global from public.order_requests
   where created_at > now() - interval '1 minute';
  if v_global >= 20 then
    raise exception 'RATE_LIMITED' using hint = 'ضغط عالي دلوقتي، جرّب بعد شوية';
  end if;

  select s.vat_rate, s.prices_include_vat into v_vat_rate, v_inclusive
    from public.site_settings s where s.id;
  v_vat_rate := coalesce(v_vat_rate, 0);

  insert into public.order_requests (
    customer_kind, contact_name, contact_phone, contact_email,
    company_name, tax_id, governorate, area, address, needed_by,
    ip_confirmed, portfolio_consent, customer_note, source,
    vat_rate_at_request
  ) values (
    coalesce((p_payload ->> 'customer_kind')::public.customer_kind, 'individual'),
    p_payload ->> 'contact_name',
    v_phone,
    nullif(p_payload ->> 'contact_email', ''),
    nullif(p_payload ->> 'company_name', ''),
    nullif(p_payload ->> 'tax_id', ''),
    nullif(p_payload ->> 'governorate', ''),
    nullif(p_payload ->> 'area', ''),
    nullif(p_payload ->> 'address', ''),
    nullif(p_payload ->> 'needed_by', '')::date,
    true,
    coalesce((p_payload ->> 'portfolio_consent')::boolean, false),
    nullif(p_payload ->> 'note', ''),
    coalesce(nullif(p_payload ->> 'source', ''), 'quote'),
    v_vat_rate
  ) returning id, code into v_id, v_code;

  -- ---- the lines ----------------------------------------------------------
  for v_line in select * from jsonb_array_elements(p_payload -> 'lines') loop
    v_no := v_no + 1;

    select p.*, c.name_ar as category_name_ar into v_product
      from public.products p
      left join public.categories c on c.id = p.category_id
     where p.id = (v_line ->> 'product_id')::uuid and p.is_published;

    if not found then
      raise exception 'PRODUCT_NOT_FOUND' using hint = 'منتج مش موجود أو مش منشور';
    end if;

    select array(select jsonb_array_elements_text(coalesce(v_line -> 'position_ids', '[]'::jsonb))::uuid)
      into v_position_ids;
    select array(select jsonb_array_elements_text(coalesce(v_line -> 'option_item_ids', '[]'::jsonb))::uuid)
      into v_option_ids;

    -- THE AUTHORITY. Whatever the browser computed is irrelevant here.
    v_q := public.price_quote(
      v_product.id,
      (v_line ->> 'qty')::int,
      nullif(v_line ->> 'method_code', ''),
      coalesce((v_line ->> 'colors')::int, 1),
      v_position_ids,
      v_option_ids
    );

    if (v_q ->> 'ok')::boolean is not true then
      raise exception 'LINE_INVALID: %', v_q ->> 'errors'
        using hint = 'في سطر اختياراته مش مظبوطة — حدّث الصفحة وجرّب تاني';
    end if;

    select pm.*, m.name_ar as method_name_ar into v_method
      from public.product_print_methods pm
      join public.print_methods m on m.code = pm.method_code
     where pm.product_id = v_product.id
       and pm.method_code = nullif(v_line ->> 'method_code', '');

    insert into public.order_request_lines (
      request_id, line_no, product_id, product_name_ar, product_slug, cover_url,
      category_name_ar, qty, moq_at_request, method_code, method_name_ar,
      colors_count, setup_fee_at_request, unit_price_at_request, options_delta,
      method_addon, line_subtotal, line_total, is_gift_wrap, gift_message, notes
    ) values (
      v_id, v_no, v_product.id, v_product.name_ar, v_product.slug, v_product.cover_url,
      v_product.category_name_ar,
      (v_q ->> 'qty')::int, v_product.moq,
      nullif(v_line ->> 'method_code', ''), v_method.method_name_ar,
      (v_q ->> 'colors')::int,
      (v_q ->> 'setup_total')::numeric,
      (v_q ->> 'unit_price')::numeric,
      (v_q ->> 'options_delta')::numeric,
      (v_q ->> 'method_addon')::numeric,
      (v_q ->> 'subtotal')::numeric,
      (v_q ->> 'subtotal')::numeric + (v_q ->> 'setup_total')::numeric,
      coalesce((v_line ->> 'is_gift_wrap')::boolean, false),
      nullif(v_line ->> 'gift_message', ''),
      nullif(v_line ->> 'notes', '')
    ) returning id into v_line_id;

    v_subtotal := v_subtotal + (v_q ->> 'subtotal')::numeric;
    v_setup    := v_setup    + (v_q ->> 'setup_total')::numeric;

    -- positions, snapshotted with their names
    for v_pos in
      select to_jsonb(pp) from public.print_positions pp
       where pp.id = any(v_position_ids) and pp.product_id = v_product.id
    loop
      insert into public.order_line_positions
        (line_id, position_id, position_name_ar, area_w_mm, area_h_mm, setup_fee_applied)
      values (
        v_line_id, (v_pos ->> 'id')::uuid, v_pos ->> 'name_ar',
        (v_pos ->> 'area_w_mm')::numeric, (v_pos ->> 'area_h_mm')::numeric,
        case when coalesce(array_length(v_position_ids, 1), 0) > 0
             then (v_q ->> 'setup_total')::numeric / array_length(v_position_ids, 1)
             else 0 end
      ) on conflict do nothing;
    end loop;

    for v_opt in
      select jsonb_build_object(
        'group_code', g.code, 'group_label_ar', g.label_ar,
        'item_value', i.value, 'item_label_ar', i.label_ar,
        'hex', i.hex, 'price_delta', i.price_delta)
        from public.product_option_items i
        join public.product_option_groups g on g.id = i.group_id
       where i.id = any(v_option_ids) and g.product_id = v_product.id
    loop
      insert into public.order_line_options
        (line_id, group_code, group_label_ar, item_value, item_label_ar, hex, price_delta)
      values (
        v_line_id, v_opt ->> 'group_code', v_opt ->> 'group_label_ar',
        v_opt ->> 'item_value', v_opt ->> 'item_label_ar',
        v_opt ->> 'hex', (v_opt ->> 'price_delta')::numeric
      ) on conflict do nothing;
    end loop;

    -- the words, exactly as typed
    for v_txt in select * from jsonb_array_elements(coalesce(v_line -> 'texts', '[]'::jsonb)) loop
      if coalesce(v_txt ->> 'content', '') <> '' then
        insert into public.order_line_texts
          (line_id, slot, content, font_key, font_name_ar, color_hex, pantone_code)
        values (
          v_line_id,
          coalesce((v_txt ->> 'slot')::int, 1),
          v_txt ->> 'content',
          nullif(v_txt ->> 'font_key', ''),
          (select f.name_ar from public.fonts f where f.key = v_txt ->> 'font_key'),
          nullif(v_txt ->> 'color_hex', ''),
          nullif(v_txt ->> 'pantone_code', '')
        ) on conflict (line_id, slot) do nothing;
      end if;
    end loop;

    -- ---- the artwork. THE CHECK THAT IS EASIEST TO FORGET ----------------
    --
    -- Without verifying that the first path segment is the CALLER's uid, any
    -- visitor could attach any other customer's logo to their own order simply
    -- by guessing a path. The storage policy stops them WRITING there; only
    -- this stops them CLAIMING it.
    for v_asset in
      select jsonb_array_elements_text(coalesce(v_line -> 'asset_paths', '[]'::jsonb))
    loop
      if (storage.foldername(v_asset))[1] is distinct from v_uid::text then
        raise exception 'ASSET_NOT_YOURS' using hint = 'ملف مش تبع الجلسة دي';
      end if;

      select * into v_upload from public.customer_uploads
       where storage_path = v_asset and owner_id = v_uid;
      if not found then
        raise exception 'ASSET_NOT_REGISTERED' using hint = 'الملف ده مش مسجّل';
      end if;

      insert into public.order_line_assets (
        line_id, upload_id, storage_path, original_name, mime, bytes,
        kind, uploaded_by, px_width, px_height, dpi_at_position
      ) values (
        v_line_id, v_upload.id, v_upload.storage_path, v_upload.original_name,
        v_upload.mime, v_upload.bytes, 'logo', v_uid,
        v_upload.px_width, v_upload.px_height,
        nullif(v_line ->> 'dpi_at_position', '')::numeric
      );
    end loop;
  end loop;

  -- ---- the totals, server-side ------------------------------------------
  v_pre_vat := v_subtotal + v_setup;
  v_vat := case when v_inclusive then 0 else round(v_pre_vat * v_vat_rate, 2) end;
  v_client_total := nullif(p_payload ->> 'client_total', '')::numeric;

  update public.order_requests set
    subtotal = v_subtotal,
    setup_total = v_setup,
    vat_amount = v_vat,
    total = v_pre_vat + v_vat,
    client_total = v_client_total,
    -- A mismatch does NOT reject the order. Rejecting punishes a customer who
    -- left a tab open across a price change; flagging tells the owner to
    -- mention it on the call. One piastre of tolerance for rounding.
    price_mismatch = v_client_total is not null
                     and abs(v_client_total - (v_pre_vat + v_vat)) > 0.01
  where id = v_id;

  return jsonb_build_object(
    'id', v_id,
    'code', v_code,
    'total', v_pre_vat + v_vat,
    'subtotal', v_subtotal,
    'setup_total', v_setup,
    'vat_amount', v_vat
  );
end $$;

-- ---------------------------------------------------------------------------
--  order_status() — tracking with no account.
--
--  Needs BOTH the id (stored on the customer's device) and the matching phone.
--  Either alone is a way to read somebody else's order: ids leak through
--  browser history, and phone numbers are guessable.
-- ---------------------------------------------------------------------------
create or replace function public.order_status(p_id uuid, p_phone text)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'code', o.code,
    'status', o.status,
    'total', o.total,
    'created_at', o.created_at,
    'needed_by', o.needed_by,
    'deposit_received', o.deposit_received,
    'lines', coalesce((
      select jsonb_agg(jsonb_build_object(
        'product_name_ar', l.product_name_ar,
        'qty', l.qty,
        'method_name_ar', l.method_name_ar,
        'line_total', l.line_total) order by l.line_no)
        from public.order_request_lines l where l.request_id = o.id), '[]'::jsonb)
  )
    from public.order_requests o
   where o.id = p_id
     and o.contact_phone = public.normalize_phone(p_phone)
$$;

-- ---------------------------------------------------------------------------
--  set_order_status() — the machine.
--
--  In a function, not an UPDATE policy: a policy can say WHO may write, only a
--  function can say which MOVE is legal. delivered and cancelled are dead ends;
--  cancelling without a reason is refused, because "why did this not happen?"
--  is the question somebody always asks three months later.
-- ---------------------------------------------------------------------------
create or replace function public.set_order_status(
  p_id uuid, p_status public.order_status, p_note text default null,
  p_reason text default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_from public.order_status;
  v_allowed public.order_status[];
begin
  if not public.is_manager() then
    raise exception 'NOT_AUTHORISED';
  end if;

  select status into v_from from public.order_requests where id = p_id;
  if v_from is null then raise exception 'ORDER_NOT_FOUND'; end if;

  if v_from in ('delivered','cancelled') then
    raise exception 'STATUS_FINAL' using hint = 'الطلب في حالة نهائية';
  end if;

  v_allowed := case v_from
    when 'new'              then array['contacted','cancelled']
    when 'contacted'        then array['quoted','cancelled']
    when 'quoted'           then array['artwork_review','cancelled']
    when 'artwork_review'   then array['artwork_approved','quoted','cancelled']
    when 'artwork_approved' then array['in_production','cancelled']
    when 'in_production'    then array['ready','cancelled']
    when 'ready'            then array['delivered','cancelled']
  end::public.order_status[];

  if not (p_status = any(v_allowed)) then
    raise exception 'STATUS_TRANSITION_NOT_ALLOWED: % -> %', v_from, p_status;
  end if;

  if p_status = 'cancelled' and coalesce(p_reason, '') = '' then
    raise exception 'CANCEL_REASON_REQUIRED' using hint = 'لازم سبب الإلغاء';
  end if;

  update public.order_requests set
    status = p_status,
    manager_note = coalesce(p_note, manager_note),
    cancel_reason = case when p_status = 'cancelled' then p_reason else cancel_reason end,
    contacted_at = case when p_status = 'contacted' then now() else contacted_at end,
    closed_at = case when p_status in ('delivered','cancelled') then now() else closed_at end
  where id = p_id;
end $$;

-- ---------------------------------------------------------------------------
--  Marks that the customer reached the WhatsApp handoff. Not proof they sent
--  it — nothing can be — but it separates "filled the form and vanished" from
--  "filled the form and opened the chat", which are different follow-ups.
-- ---------------------------------------------------------------------------
create or replace function public.mark_whatsapp_sent(p_id uuid, p_phone text)
returns void
language sql security definer set search_path = public as $$
  update public.order_requests set whatsapp_sent_at = now()
   where id = p_id and contact_phone = public.normalize_phone(p_phone)
     and whatsapp_sent_at is null
$$;

-- ------------------------------------------------------------ الصلاحيات ----

-- Revoke from PUBLIC first. These functions were created after
-- 20260810100006_rls.sql, so they still carry the default PUBLIC grant that
-- makes a `revoke ... from anon` a no-op.
revoke execute on function public.order_status_event()                              from public, anon;
revoke execute on function public.register_upload(text, text, text, bigint, int, int) from public, anon;
revoke execute on function public.create_order_request(jsonb)                       from public, anon;
revoke execute on function public.order_status(uuid, text)                          from public, anon;
revoke execute on function public.mark_whatsapp_sent(uuid, text)                    from public, anon;
revoke execute on function public.set_order_status(uuid, public.order_status, text, text)
  from public, anon;

-- A visitor orders without an account, so these four are open. Every one of
-- them carries its own gate inside: register_upload checks the path belongs to
-- the caller, create_order_request rate-limits and re-prices, and the two
-- read-backs need the id AND the matching phone.
grant execute on function public.register_upload(text, text, text, bigint, int, int)
  to anon, authenticated;
grant execute on function public.create_order_request(jsonb)    to anon, authenticated;
grant execute on function public.order_status(uuid, text)       to anon, authenticated;
grant execute on function public.mark_whatsapp_sent(uuid, text) to anon, authenticated;

-- Manager only. The is_manager() check inside is the belt; this grant is the
-- braces.
grant execute on function public.set_order_status(uuid, public.order_status, text, text)
  to authenticated;
