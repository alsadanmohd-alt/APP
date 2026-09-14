-- Existing installations only. New installations use schema.sql instead.
-- Adds a mirror review system: the owner can rate the renter after a
-- conversation, the same shape as the existing renter-rates-item reviews.
begin;

create table if not exists public.renter_reviews(id uuid primary key default gen_random_uuid(),booking_id uuid not null unique references public.bookings(id) on delete cascade,renter_id uuid not null references auth.users(id),author_id uuid not null references auth.users(id),rating int not null check(rating between 1 and 5),body text not null check(char_length(trim(body)) between 1 and 1000),created_at timestamptz not null default now());
alter table public.renter_reviews enable row level security;

drop policy if exists renter_reviews_read on public.renter_reviews;
create policy renter_reviews_read on public.renter_reviews for select using(true);
drop policy if exists renter_reviews_write on public.renter_reviews;
create policy renter_reviews_write on public.renter_reviews for insert to authenticated with check(author_id=auth.uid() and exists(select 1 from public.bookings b where b.id=booking_id and b.owner_id=auth.uid() and b.renter_id=renter_reviews.renter_id));

grant select on public.renter_reviews to anon,authenticated;
grant insert on public.renter_reviews to authenticated;

commit;
