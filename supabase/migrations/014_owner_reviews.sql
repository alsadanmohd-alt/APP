-- Existing installations only. New installations use schema.sql instead.
-- Reviews stop being about a specific item and become about the owner (advertiser)
-- instead, mirroring renter_reviews. A renter rates the owner after a booking, and
-- the result is shown publicly on the owner's profile for everyone to see.
begin;

alter table public.reviews add column if not exists owner_id uuid references auth.users(id);
update public.reviews r set owner_id=b.owner_id from public.bookings b where b.id=r.booking_id and r.owner_id is null;
alter table public.reviews alter column owner_id set not null;

-- Must drop the old policy before the column, since it references item_id in its check.
drop policy if exists reviews_write on public.reviews;

alter table public.reviews drop column if exists item_id;

create policy reviews_write on public.reviews for insert to authenticated with check(author_id=auth.uid() and exists(select 1 from public.bookings b where b.id=booking_id and b.owner_id=reviews.owner_id and b.renter_id=auth.uid()));

commit;
