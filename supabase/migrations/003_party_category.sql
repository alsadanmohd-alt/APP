-- Add the party-equipment category to an existing Qareeb database.
alter table public.items drop constraint if exists items_category_check;
alter table public.items add constraint items_category_check
check(category in ('تصوير','رحلات','أدوات ومعدات','رياضة','منزل','إلكترونيات','تجهيز الحفلات'));
