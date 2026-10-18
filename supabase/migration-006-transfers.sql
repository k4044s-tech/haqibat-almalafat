-- ============================================================
-- نَسَق — إرسال ملف مجهَّز من المشرف إلى مستخدم
-- شغّل هذا الملف مرة واحدة في Supabase → SQL Editor
-- ============================================================
create table if not exists public.file_transfers (
  id           bigint generated always as identity primary key,
  from_uid     uuid not null references auth.users(id) on delete cascade,
  to_uid       uuid not null references auth.users(id) on delete cascade,
  file_id      text not null,
  file_name    text,
  note         text,
  payload      jsonb not null,          -- محتوى الملف: النصوص والصور وروابط الشواهد
  created_at   timestamptz not null default now(),
  received_at  timestamptz
);
create index if not exists file_transfers_to on public.file_transfers (to_uid, received_at);

alter table public.file_transfers enable row level security;
drop policy if exists ft_select on public.file_transfers;
drop policy if exists ft_insert on public.file_transfers;
drop policy if exists ft_update on public.file_transfers;
drop policy if exists ft_delete on public.file_transfers;
-- المستلم يرى ما أُرسل له، والمشرف يرى الكل
create policy ft_select on public.file_transfers for select using (to_uid = auth.uid() or public.is_admin());
-- الإرسال للمشرف فقط
create policy ft_insert on public.file_transfers for insert with check (public.is_admin() and from_uid = auth.uid());
-- المستلم يعلّم الملف «مستلَمًا»
create policy ft_update on public.file_transfers for update using (to_uid = auth.uid() or public.is_admin()) with check (to_uid = auth.uid() or public.is_admin());
create policy ft_delete on public.file_transfers for delete using (to_uid = auth.uid() or public.is_admin());
