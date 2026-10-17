-- =====================================================================
-- الأدوات والباقات: ترخيص لعام دراسي، وباقة تفعّل أكثر من منتج
-- (آمن للتشغيل أكثر من مرة)
-- =====================================================================

alter table public.products add column if not exists includes jsonb not null default '[]'::jsonb;
alter table public.products add column if not exists term text not null default 'life';
do $$ begin
  alter table public.products add constraint products_term_chk check (term in ('life','year'));
exception when duplicate_object then null; end $$;

-- راصد نافس (أداة بترخيص سنوي) وباقة نافس (الملف + الأداة)
-- الأسعار مبدئية، وتُعدَّل من «إدارة المتجر ← الأسعار»
insert into public.products (file_id, price, free, active, includes, term)
values ('nafes', 49, false, true, '[]'::jsonb, 'year'),
       ('pack-nafes', 59, false, true, '["nafs","nafes"]'::jsonb, 'year')
on conflict (file_id) do update set includes = excluded.includes, term = excluded.term;

-- اعتماد الطلب: يفعّل كل عنصر وما تتضمنه الباقة، والأدوات السنوية بتاريخ انتهاء
create or replace function public.decide_order(oid bigint, ok boolean, note text default null) returns void
language plpgsql security definer set search_path = public as $$
declare o public.orders; f text; g text; p jsonb; lic text; inc jsonb; tm text;
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
    select coalesce(nullif(value->>'license_until',''), (current_date + 365)::text) into lic
      from public.settings where key = 'store';
    lic := coalesce(lic, (current_date + 365)::text);
    select coalesce(perms, '{}'::jsonb) into p from public.profiles where id = o.uid;
    for f in select jsonb_array_elements_text(o.items) loop
      select coalesce(includes, '[]'::jsonb) into inc from public.products where file_id = f;
      for g in select f union select jsonb_array_elements_text(coalesce(inc, '[]'::jsonb)) loop
        select term into tm from public.products where file_id = g;
        if tm = 'year' then
          p := jsonb_set(p, array[g], jsonb_build_object('e', true, 'p', true, 'until', lic), true);
        else
          p := jsonb_set(p, array[g], '{"e":true,"p":true}'::jsonb, true);
        end if;
      end loop;
    end loop;
    update public.profiles
       set perms = p, status = 'active',
           requests = coalesce((select jsonb_agg(x) from jsonb_array_elements_text(requests) x where not (o.items ? x)), '[]'::jsonb)
     where id = o.uid;
  end if;
end $$;
grant execute on function public.decide_order(bigint, boolean, text) to authenticated;
