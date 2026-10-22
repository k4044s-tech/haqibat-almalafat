-- ============================================================
-- نَسَق — «ملفاتي المحفوظة»: حفظ نسخ من الملفات والكشوف والرجوع إليها
-- شغّل هذا الملف مرة واحدة في Supabase → SQL Editor
-- ============================================================
create table if not exists public.saved_files (
  id          bigint generated always as identity primary key,
  uid         uuid not null default auth.uid() references auth.users(id) on delete cascade,
  file_id     text not null,
  name        text not null,
  size        integer not null default 0,
  payload     jsonb not null,            -- النصوص والصور وروابط الشواهد وقوائم الطلاب
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists saved_files_uid on public.saved_files (uid, updated_at desc);

alter table public.saved_files enable row level security;
drop policy if exists sv_select on public.saved_files;
drop policy if exists sv_insert on public.saved_files;
drop policy if exists sv_update on public.saved_files;
drop policy if exists sv_delete on public.saved_files;
-- كل مستخدم يرى ويعدّل نسخه فقط
create policy sv_select on public.saved_files for select using (uid = auth.uid());
create policy sv_insert on public.saved_files for insert with check (
  uid = auth.uid()
  and (select count(*) from public.saved_files s where s.uid = auth.uid()) < 200);
create policy sv_update on public.saved_files for update using (uid = auth.uid()) with check (uid = auth.uid());
create policy sv_delete on public.saved_files for delete using (uid = auth.uid());
