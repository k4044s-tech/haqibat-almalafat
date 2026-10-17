-- ============================================================
-- نَسَق — التجهيز الذكي (Claude)
-- شغّل هذا الملف مرة واحدة في Supabase → SQL Editor
-- ============================================================

-- سجل عمليات التجهيز: كل عملية = ملف واحد لمستخدم واحد (قد تُرسل على عدة أجزاء)
create table if not exists public.ai_jobs (
  id             bigint generated always as identity primary key,
  uid            uuid not null references auth.users(id) on delete cascade,
  file_id        text not null,
  created_at     timestamptz not null default now(),
  parts          int  not null default 0,
  input_tokens   int  not null default 0,
  output_tokens  int  not null default 0,
  cost_usd       numeric(10,4) not null default 0,
  status         text not null default 'running' check (status in ('running','done','failed'))
);
create index if not exists ai_jobs_uid_file on public.ai_jobs (uid, file_id);
create index if not exists ai_jobs_created  on public.ai_jobs (created_at desc);

alter table public.ai_jobs enable row level security;
drop policy if exists ai_jobs_select on public.ai_jobs;
-- المستخدم يرى عملياته فقط، والمشرف يرى الكل. الكتابة من دالة الخادم فقط (service role).
create policy ai_jobs_select on public.ai_jobs for select using (uid = auth.uid() or public.is_admin());

-- إعدادات التجهيز الذكي (يمكن تعديلها من جدول settings)
-- limit: عدد مرات التجهيز المسموحة لكل ملف لكل مستخدم
-- model: نموذج Claude المستخدم
insert into public.settings (key, value)
values ('ai', '{"limit":3,"model":"claude-sonnet-5-5","enabled":true}'::jsonb)
on conflict (key) do nothing;
