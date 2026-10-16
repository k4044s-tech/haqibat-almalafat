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
