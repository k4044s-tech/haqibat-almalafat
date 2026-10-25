-- ============================================================
-- نَسَق — طلبات التجهيز الذكي (المشترك يرسل مرفقاته وبياناته، والمشرف يجهّز ويرسل الملف)
-- شغّل هذا الملف مرة واحدة في Supabase → SQL Editor
-- ============================================================
create table if not exists public.prep_requests (
  id          bigint generated always as identity primary key,
  uid         uuid not null references auth.users(id) on delete cascade,
  email       text,
  name        text,
  file_id     text not null,
  file_name   text,
  data        jsonb not null default '{}'::jsonb,   -- البيانات المكتوبة وما جهّزه والملاحظات والجنس
  files       jsonb not null default '[]'::jsonb,   -- [{path,name,size,type,item,label}] في مخزن prep
  status      text not null default 'new' check (status in ('new','working','done','canceled')),
  admin_note  text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists prep_requests_status on public.prep_requests (status, created_at);
create index if not exists prep_requests_uid on public.prep_requests (uid, file_id);

alter table public.prep_requests enable row level security;
drop policy if exists prep_select on public.prep_requests;
drop policy if exists prep_insert on public.prep_requests;
drop policy if exists prep_update on public.prep_requests;
drop policy if exists prep_delete on public.prep_requests;
create policy prep_select on public.prep_requests for select using (uid = auth.uid() or public.is_admin());
create policy prep_insert on public.prep_requests for insert with check (uid = auth.uid() and public.is_active() and status = 'new');
create policy prep_update on public.prep_requests for update using (public.is_admin()) with check (public.is_admin());
create policy prep_delete on public.prep_requests for delete using (public.is_admin() or (uid = auth.uid() and status = 'new'));

-- مخزن المرفقات (خاص): المسار يبدأ بمعرّف المستخدم
insert into storage.buckets (id, name, public, file_size_limit)
values ('prep', 'prep', false, 15728640)
on conflict (id) do update set public = false, file_size_limit = 15728640;

drop policy if exists prep_obj_insert on storage.objects;
drop policy if exists prep_obj_select on storage.objects;
drop policy if exists prep_obj_delete on storage.objects;
create policy prep_obj_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'prep' and (storage.foldername(name))[1] = auth.uid()::text and public.is_active());
create policy prep_obj_select on storage.objects for select to authenticated
  using (bucket_id = 'prep' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));
create policy prep_obj_delete on storage.objects for delete to authenticated
  using (bucket_id = 'prep' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));
