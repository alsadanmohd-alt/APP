-- Existing installations only. New installations use schema.sql instead.
-- Adds a narrow admin capability: view/delete any listing, list new listings,
-- and list all users. Admin status can only be granted from the Supabase SQL
-- editor (or service role) by inserting a row into admins — never from the
-- client, and no insert/update/delete policy exists on this table at all.
-- Conversations and messages remain unreadable by anyone but their two
-- participants: this migration does not touch bookings_read or messages_read.
begin;

create table if not exists public.admins(id uuid primary key references auth.users(id) on delete cascade,created_at timestamptz not null default now());
alter table public.admins enable row level security;

drop policy if exists admins_read_self on public.admins;
create policy admins_read_self on public.admins for select to authenticated using(id=auth.uid());

drop policy if exists items_delete on public.items;
create policy items_delete on public.items for delete to authenticated using(owner_id=auth.uid() or exists(select 1 from public.admins a where a.id=auth.uid()));

-- Admin-only: the full user list with phone numbers, for moderation and support. Never exposes
-- conversations or messages — those stay unreadable by anyone but their two participants.
create or replace function public.admin_list_users() returns table(id uuid,display_name text,phone text,created_at timestamptz)
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not exists(select 1 from admins where id=auth.uid()) then raise exception 'غير مصرح'; end if;
 return query select u.id,coalesce(p.display_name,'—'),u.phone,u.created_at from auth.users u left join profiles p on p.id=u.id order by u.created_at desc;
end $$;

revoke all on function public.admin_list_users() from public;
grant execute on function public.admin_list_users() to authenticated;
grant select on public.admins to authenticated;

commit;
