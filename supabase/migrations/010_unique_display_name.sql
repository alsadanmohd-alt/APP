-- Existing installations only. New installations use schema.sql instead.
-- Enforces that no two users share the same public display name
-- (case-insensitive, whitespace-trimmed). Fails if duplicates already
-- exist; rename one of each colliding pair first if it does.
begin;

create unique index if not exists profiles_display_name_unique on public.profiles(lower(trim(display_name)));

commit;
