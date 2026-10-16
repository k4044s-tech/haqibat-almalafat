-- وصف كل ملف في المتجر (الوصف، لمن، طريقة الإدخال، ملاحظة) — آمن للتشغيل أكثر من مرة
alter table public.products add column if not exists info jsonb not null default '{}'::jsonb;
