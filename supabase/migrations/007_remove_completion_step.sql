-- Existing installations only. New installations use schema.sql instead.
-- Removes the owner "confirm rental completion" step entirely: bookings no
-- longer carry a status, and reviews only require an existing conversation
-- (started via start_conversation) rather than a completed one.
begin;

drop function if exists public.mark_completed(uuid);

drop policy if exists reviews_write on public.reviews;
create policy reviews_write on public.reviews for insert to authenticated with check(author_id=auth.uid() and exists(select 1 from public.bookings b where b.id=booking_id and b.item_id=reviews.item_id and b.renter_id=auth.uid()));

alter table public.bookings drop constraint if exists bookings_status_check;
alter table public.bookings alter column status drop default;
alter table public.bookings drop column if exists status;

commit;
