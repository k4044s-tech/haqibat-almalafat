-- ============================================================
-- نَسَق — النسخة الإلكترونية للملفات (نشر الملف كموقع برابط)
-- شغّل هذا الملف مرة واحدة في Supabase → SQL Editor
-- ============================================================
create table if not exists public.published_files (
  id          text primary key check (id ~ '^[A-Za-z0-9]{8,16}$'),
  uid         uuid not null default auth.uid() references auth.users(id) on delete cascade,
  file_id     text not null,
  title       text,
  owner_name  text,
  payload     jsonb not null,           -- الإعدادات والنصوص والصور وروابط الشواهد
  enabled     boolean not null default true,
  views       integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (uid, file_id)
);

-- هل يملك المستخدم صلاحية النشر لهذا الملف؟
create or replace function public.can_publish(fid text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and (p.role = 'admin'
           or (p.status = 'active'
               and (coalesce((p.perms -> 'all' ->> 'pub')::boolean, false)
                    or coalesce((p.perms -> fid ->> 'pub')::boolean, false)))));
$$;

alter table public.published_files enable row level security;
drop policy if exists pf_select on public.published_files;
drop policy if exists pf_insert on public.published_files;
drop policy if exists pf_update on public.published_files;
drop policy if exists pf_delete on public.published_files;
-- صاحب الملف والمشرف فقط يرون الصفوف (الزوار يقرؤون عبر الدالة get_published)
create policy pf_select on public.published_files for select using (uid = auth.uid() or public.is_admin());
create policy pf_insert on public.published_files for insert with check (uid = auth.uid() and public.can_publish(file_id));
create policy pf_update on public.published_files for update using (uid = auth.uid()) with check (uid = auth.uid() and public.can_publish(file_id));
create policy pf_delete on public.published_files for delete using (uid = auth.uid() or public.is_admin());

-- قراءة الملف المنشور برابطه (للجميع) مع زيادة عدد المشاهدات
create or replace function public.get_published(p_id text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r record;
begin
  update public.published_files set views = views + 1
   where id = p_id and enabled
   returning file_id, title, owner_name, payload, updated_at into r;
  if not found then return null; end if;
  return jsonb_build_object('file_id', r.file_id, 'title', r.title, 'owner', r.owner_name,
                            'payload', r.payload, 'updated_at', r.updated_at);
end $$;
revoke all on function public.get_published(text) from public;
grant execute on function public.get_published(text) to anon, authenticated;
