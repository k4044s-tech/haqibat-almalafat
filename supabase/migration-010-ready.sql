-- ============================================================
-- نَسَق — «النسخة الجاهزة»: محتوى معتمد من المشرف يظهر لكل المشتركين
-- شغّل هذا الملف مرة واحدة في Supabase → SQL Editor
-- ============================================================
create table if not exists public.ready_templates (
  file_id     text primary key,
  data        jsonb not null,          -- {v, file, data:{مفتاح الحقل: المحتوى}}
  updated_at  timestamptz not null default now(),
  updated_by  uuid default auth.uid()
);
alter table public.ready_templates enable row level security;
drop policy if exists rt_select on public.ready_templates;
drop policy if exists rt_write  on public.ready_templates;
-- القراءة للجميع (المحتوى عام ولا يحتوي بيانات شخصية)
create policy rt_select on public.ready_templates for select using (true);
-- الكتابة للمشرف فقط
create policy rt_write on public.ready_templates for all using (public.is_admin()) with check (public.is_admin());
grant select on public.ready_templates to anon, authenticated;
grant insert, update, delete on public.ready_templates to authenticated;
