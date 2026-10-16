-- =====================================================================
-- حقيبة الملفات المدرسية — قاعدة بيانات Supabase (PostgreSQL)
-- شغّل هذا الملف كاملًا مرة واحدة من: Supabase → SQL Editor → New query
-- أول حساب يُسجَّل في الحقيبة يصبح المشرف تلقائيًا.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- المستخدمون
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  id          uuid primary key references auth.users on delete cascade,
  email       text,
  name        text,
  phone       text,
  title       text,
  gender      text not null default 'm' check (gender in ('m','f')),
  school      text,
  dept        text,
  status      text not null default 'active' check (status in ('pending','active','rejected','suspended')),
  role        text not null default 'user'   check (role in ('user','admin')),
  perms       jsonb not null default '{}'::jsonb,   -- {"file-id":{"e":true,"p":true}, "all":{...}}
  requests    jsonb not null default '[]'::jsonb,   -- ["file-id", ...]
  created_at  timestamptz not null default now()
);

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin' and status = 'active');
$$;

create or replace function public.is_active() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and status = 'active');
$$;

-- إنشاء الملف الشخصي تلقائيًا عند التسجيل (أول مستخدم يصبح مشرفًا)
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, name, phone, title, gender, school, dept, role, status)
  values (
    new.id,
    lower(new.email),
    new.raw_user_meta_data->>'name',
    new.raw_user_meta_data->>'phone',
    new.raw_user_meta_data->>'title',
    case when new.raw_user_meta_data->>'gender' = 'f' then 'f' else 'm' end,
    new.raw_user_meta_data->>'school',
    new.raw_user_meta_data->>'dept',
    case when exists (select 1 from public.profiles where role = 'admin') then 'user' else 'admin' end,
    'active'
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- المستخدم العادي لا يغيّر دوره أو حالته أو صلاحياته بنفسه
create or replace function public.profiles_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    new.id     := old.id;
    new.email  := old.email;
    new.role   := old.role;
    new.status := old.status;
    new.perms  := old.perms;
    new.created_at := old.created_at;
  end if;
  return new;
end $$;

drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard before update on public.profiles
  for each row execute function public.profiles_guard();

alter table public.profiles enable row level security;
drop policy if exists profiles_select on public.profiles;
drop policy if exists profiles_update on public.profiles;
drop policy if exists profiles_delete on public.profiles;
drop policy if exists profiles_insert on public.profiles;
create policy profiles_select on public.profiles for select using (id = auth.uid() or public.is_admin());
create policy profiles_insert on public.profiles for insert with check (id = auth.uid() and role = 'user' and status = 'active' and perms = '{}'::jsonb);
create policy profiles_update on public.profiles for update using (id = auth.uid() or public.is_admin());
create policy profiles_delete on public.profiles for delete using (public.is_admin());

-- ---------------------------------------------------------------------
-- صور الشواهد (باركود)
-- ---------------------------------------------------------------------
create table if not exists public.evidence (
  id          uuid primary key default gen_random_uuid(),
  uid         uuid not null references auth.users on delete cascade,
  img         text not null check (length(img) < 1000000),
  title text, page text, cap text, school text, name text, file text,
  created_at  timestamptz not null default now()
);
alter table public.evidence enable row level security;
drop policy if exists evidence_insert on public.evidence;
drop policy if exists evidence_select on public.evidence;
drop policy if exists evidence_delete on public.evidence;
create policy evidence_insert on public.evidence for insert with check (uid = auth.uid() and public.is_active());
create policy evidence_select on public.evidence for select using (uid = auth.uid() or public.is_admin());
create policy evidence_delete on public.evidence for delete using (uid = auth.uid() or public.is_admin());

-- من يمسح الباركود يفتح شاهدًا بعينه فقط (دون استعراض القائمة)
create or replace function public.get_evidence(eid uuid) returns setof public.evidence
language sql stable security definer set search_path = public as $$
  select * from public.evidence where id = eid;
$$;
grant execute on function public.get_evidence(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------
-- منصة البطاقات
-- ---------------------------------------------------------------------
create table if not exists public.cards (
  id          uuid primary key default gen_random_uuid(),
  uid         uuid not null references auth.users on delete cascade,
  name        text,
  tpl         text,
  data        jsonb not null check (pg_column_size(data) < 1000000),
  created_at  timestamptz not null default now()
);
alter table public.cards enable row level security;
drop policy if exists cards_insert on public.cards;
drop policy if exists cards_select on public.cards;
drop policy if exists cards_update on public.cards;
drop policy if exists cards_delete on public.cards;
create policy cards_insert on public.cards for insert with check (uid = auth.uid() and public.is_active());
create policy cards_select on public.cards for select using (uid = auth.uid() or public.is_admin());
create policy cards_update on public.cards for update using (uid = auth.uid()) with check (uid = auth.uid());
create policy cards_delete on public.cards for delete using (uid = auth.uid() or public.is_admin());

create or replace function public.get_card(cid uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select data from public.cards where id = cid;
$$;
grant execute on function public.get_card(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------
-- المتجر: الأسعار والإعدادات والطلبات
-- ---------------------------------------------------------------------
create table if not exists public.products (
  file_id     text primary key,
  price       numeric(10,2) not null default 0 check (price >= 0),
  free        boolean not null default false,
  active      boolean not null default true,
  updated_at  timestamptz not null default now()
);
alter table public.products enable row level security;
drop policy if exists products_read on public.products;
drop policy if exists products_admin on public.products;
create policy products_read  on public.products for select using (true);
create policy products_admin on public.products for all using (public.is_admin()) with check (public.is_admin());

create table if not exists public.settings (
  key   text primary key,
  value jsonb not null default '{}'::jsonb
);
alter table public.settings enable row level security;
drop policy if exists settings_read on public.settings;
drop policy if exists settings_admin on public.settings;
create policy settings_read  on public.settings for select using (true);
create policy settings_admin on public.settings for all using (public.is_admin()) with check (public.is_admin());

insert into public.settings (key, value) values
  ('store', '{"def": 10, "currency": "ر.س"}'),
  ('bank',  '{"bank": "", "holder": "", "iban": "", "whatsapp": "966554801019", "note": ""}')
on conflict (key) do nothing;

-- ملفات مجانية للتجربة (عدّلها من «إدارة المتجر»)
insert into public.products (file_id, price, free) values
  ('weeks', 0, true), ('ks-absence', 0, true), ('certs', 0, true)
on conflict (file_id) do nothing;

create table if not exists public.orders (
  id          bigint generated always as identity primary key,
  uid         uuid not null references auth.users on delete cascade,
  email       text,
  name        text,
  items       jsonb not null check (jsonb_typeof(items) = 'array' and jsonb_array_length(items) between 1 and 100),
  total       numeric(10,2) not null default 0,
  receipt     text check (receipt is null or length(receipt) < 600000),
  ref         text,
  note        text,
  status      text not null default 'pending' check (status in ('pending','approved','rejected')),
  admin_note  text,
  created_at  timestamptz not null default now(),
  decided_at  timestamptz
);

-- المبلغ يُحسب في القاعدة من الأسعار المعتمدة، لا من المتصفح
create or replace function public.orders_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare d numeric; t numeric := 0; f text; p public.products;
begin
  select coalesce((value->>'def')::numeric, 0) into d from public.settings where key = 'store';
  for f in select distinct jsonb_array_elements_text(new.items) loop
    select * into p from public.products where file_id = f;
    if p.file_id is null then t := t + coalesce(d, 0);
    elsif p.active and not p.free then t := t + p.price;
    end if;
  end loop;
  new.total  := t;
  new.status := 'pending';
  new.admin_note := null;
  new.decided_at := null;
  select email, name into new.email, new.name from public.profiles where id = new.uid;
  return new;
end $$;
drop trigger if exists orders_before_insert on public.orders;
create trigger orders_before_insert before insert on public.orders
  for each row execute function public.orders_before_insert();

alter table public.orders enable row level security;
drop policy if exists orders_insert on public.orders;
drop policy if exists orders_select on public.orders;
drop policy if exists orders_admin  on public.orders;
drop policy if exists orders_delete on public.orders;
create policy orders_insert on public.orders for insert with check (uid = auth.uid() and public.is_active());
create policy orders_select on public.orders for select using (uid = auth.uid() or public.is_admin());
create policy orders_admin  on public.orders for update using (public.is_admin()) with check (public.is_admin());
create policy orders_delete on public.orders for delete using (public.is_admin());

-- اعتماد الطلب أو رفضه: عند الاعتماد تُمنح صلاحية التعديل والطباعة لكل ملف في الطلب
create or replace function public.decide_order(oid bigint, ok boolean, note text default null) returns void
language plpgsql security definer set search_path = public as $$
declare o public.orders; f text; p jsonb;
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  select * into o from public.orders where id = oid for update;
  if o.id is null then raise exception 'order not found'; end if;
  update public.orders
     set status = case when ok then 'approved' else 'rejected' end,
         admin_note = decide_order.note, decided_at = now()
   where id = oid;
  if ok then
    select coalesce(perms, '{}'::jsonb) into p from public.profiles where id = o.uid;
    for f in select jsonb_array_elements_text(o.items) loop
      p := jsonb_set(p, array[f], '{"e":true,"p":true}'::jsonb, true);
    end loop;
    update public.profiles
       set perms = p, status = 'active',
           requests = coalesce((select jsonb_agg(x) from jsonb_array_elements_text(requests) x where not (o.items ? x)), '[]'::jsonb)
     where id = o.uid;
  end if;
end $$;
grant execute on function public.decide_order(bigint, boolean, text) to authenticated;

create index if not exists orders_uid_idx     on public.orders (uid, created_at desc);
create index if not exists orders_status_idx  on public.orders (status, created_at desc);
create index if not exists evidence_uid_idx   on public.evidence (uid);
create index if not exists cards_uid_idx      on public.cards (uid, created_at desc);

-- ---------------------------------------------------------------------
-- صلاحيات واجهة البيانات (RLS أعلاه هي التي تقرر ما يُسمح به فعليًا)
-- ---------------------------------------------------------------------
grant usage on schema public to anon, authenticated;
grant select on public.products, public.settings to anon, authenticated;
grant select, insert, update, delete on public.profiles, public.evidence, public.cards, public.orders, public.products, public.settings to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant execute on function public.is_admin(), public.is_active() to anon, authenticated;

-- =====================================================================
-- الخصومات: خصم لكل ملف، وخصم عام على المتجر بتاريخ انتهاء، وأكواد خصم
-- (آمن للتشغيل أكثر من مرة)
-- =====================================================================

alter table public.products add column if not exists discount numeric(5,2) not null default 0;
do $$ begin
  alter table public.products add constraint products_discount_chk check (discount >= 0 and discount <= 100);
exception when duplicate_object then null; end $$;

alter table public.orders add column if not exists coupon   text;
alter table public.orders add column if not exists subtotal numeric(10,2);
alter table public.orders add column if not exists discount numeric(10,2) not null default 0;

create table if not exists public.coupons (
  code        text primary key check (code = upper(code) and length(code) between 3 and 30),
  pct         numeric(5,2) not null check (pct > 0 and pct <= 100),
  active      boolean not null default true,
  expires     date,
  max_uses    integer check (max_uses is null or max_uses > 0),
  used        integer not null default 0,
  note        text,
  created_at  timestamptz not null default now()
);
alter table public.coupons enable row level security;
drop policy if exists coupons_admin on public.coupons;
create policy coupons_admin on public.coupons for all using (public.is_admin()) with check (public.is_admin());
grant select, insert, update, delete on public.coupons to authenticated;

-- الخصم العام الفعّال الآن (من إعدادات المتجر: sale_pct و sale_until)
create or replace function public.store_sale_pct() returns numeric
language sql stable security definer set search_path = public as $$
  select case
    when coalesce((value->>'sale_pct')::numeric, 0) > 0
     and (nullif(value->>'sale_until','') is null or (value->>'sale_until')::date >= (now() at time zone 'Asia/Riyadh')::date)
    then least((value->>'sale_pct')::numeric, 100) else 0 end
  from public.settings where key = 'store';
$$;

-- التحقق من كود الخصم دون كشف قائمة الأكواد
create or replace function public.check_coupon(c text) returns numeric
language sql stable security definer set search_path = public as $$
  select pct from public.coupons
   where code = upper(trim(c)) and active
     and (expires is null or expires >= (now() at time zone 'Asia/Riyadh')::date)
     and (max_uses is null or used < max_uses);
$$;
grant execute on function public.check_coupon(text) to anon, authenticated;
grant execute on function public.store_sale_pct() to anon, authenticated;

-- حساب الطلب داخل القاعدة: سعر الملف بعد خصمه (أو الخصم العام أيهما أكبر)، ثم كود الخصم
create or replace function public.orders_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare d numeric; sale numeric; t numeric := 0; f text; p public.products; pc numeric; cp numeric;
begin
  select coalesce((value->>'def')::numeric, 0) into d from public.settings where key = 'store';
  sale := coalesce(public.store_sale_pct(), 0);
  for f in select distinct jsonb_array_elements_text(new.items) loop
    select * into p from public.products where file_id = f;
    if p.file_id is null then
      t := t + round(coalesce(d, 0) * (1 - sale / 100), 2);
    elsif p.active and not p.free then
      pc := greatest(coalesce(p.discount, 0), sale);
      t := t + round(p.price * (1 - pc / 100), 2);
    end if;
  end loop;
  new.subtotal := t;
  new.discount := 0;
  if new.coupon is not null and length(trim(new.coupon)) > 0 then
    new.coupon := upper(trim(new.coupon));
    cp := public.check_coupon(new.coupon);
    if cp is null then raise exception 'invalid coupon'; end if;
    new.discount := round(t * cp / 100, 2);
  else
    new.coupon := null;
  end if;
  new.total  := greatest(t - new.discount, 0);
  new.status := 'pending';
  new.admin_note := null;
  new.decided_at := null;
  select email, name into new.email, new.name from public.profiles where id = new.uid;
  return new;
end $$;

-- عند اعتماد طلب فيه كود خصم يُحتسب استخدام الكود
create or replace function public.decide_order(oid bigint, ok boolean, note text default null) returns void
language plpgsql security definer set search_path = public as $$
declare o public.orders; f text; p jsonb;
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  select * into o from public.orders where id = oid for update;
  if o.id is null then raise exception 'order not found'; end if;
  update public.orders
     set status = case when ok then 'approved' else 'rejected' end,
         admin_note = decide_order.note, decided_at = now()
   where id = oid;
  if ok then
    if o.coupon is not null and o.status <> 'approved' then
      update public.coupons set used = used + 1 where code = o.coupon;
    end if;
    select coalesce(perms, '{}'::jsonb) into p from public.profiles where id = o.uid;
    for f in select jsonb_array_elements_text(o.items) loop
      p := jsonb_set(p, array[f], '{"e":true,"p":true}'::jsonb, true);
    end loop;
    update public.profiles
       set perms = p, status = 'active',
           requests = coalesce((select jsonb_agg(x) from jsonb_array_elements_text(requests) x where not (o.items ? x)), '[]'::jsonb)
     where id = o.uid;
  end if;
end $$;
grant execute on function public.decide_order(bigint, boolean, text) to authenticated;
