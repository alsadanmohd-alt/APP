-- Existing installations only. New installations use schema.sql instead.
-- Adds a public display name per user, chosen once at first login and shown
-- on their listings and their public profile page.
begin;

create table if not exists public.profiles(id uuid primary key references auth.users(id) on delete cascade,display_name text not null check(char_length(trim(display_name)) between 2 and 40),created_at timestamptz not null default now());
alter table public.profiles enable row level security;

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select using(true);
drop policy if exists profiles_write on public.profiles;
create policy profiles_write on public.profiles for insert to authenticated with check(id=auth.uid());

grant select on public.profiles to anon,authenticated;
grant insert on public.profiles to authenticated;

commit;
