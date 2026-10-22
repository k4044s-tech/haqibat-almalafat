-- ============================================================
-- نَسَق — بيانات معاينة رابط الملف المنشور (للواتساب ووسائل التواصل)
-- شغّل هذا الملف مرة واحدة في Supabase → SQL Editor (بعد migration-007)
-- تُرجع العنوان واسم صاحب الملف والمدرسة فقط، دون محتوى الملف ودون زيادة المشاهدات
-- ============================================================
create or replace function public.get_published_meta(p_id text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'title',  title,
    'owner',  owner_name,
    'job',    payload -> 'set' ->> 'job',
    'school', payload -> 'set' ->> 'school',
    'year',   payload -> 'set' ->> 'year',
    'gender', payload -> 'set' ->> 'gender')
  from public.published_files where id = p_id and enabled;
$$;
revoke all on function public.get_published_meta(text) from public;
grant execute on function public.get_published_meta(text) to anon, authenticated;
