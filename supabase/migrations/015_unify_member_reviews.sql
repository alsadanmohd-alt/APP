-- Existing installations only. New installations use schema.sql instead.
-- Drops the owner-vs-renter review split: one member rates another after a
-- booking, whichever side of it they were on. Merges renter_reviews into
-- reviews and renames reviews.owner_id to the more general subject_id.
begin;

alter table public.reviews rename column owner_id to subject_id;

-- Replace the old unique(booking_id) with unique(booking_id, author_id), since
-- now both participants of a booking may each leave one review of the other.
do $$
declare c text;
begin
 select con.conname into c from pg_constraint con join pg_class rel on rel.oid=con.conrelid
  where rel.relname='reviews' and con.contype='u'
   and con.conkey=(select array_agg(attnum) from pg_attribute where attrelid=rel.oid and attname='booking_id');
 if c is not null then execute format('alter table public.reviews drop constraint %I',c); end if;
end $$;
alter table public.reviews add constraint reviews_booking_author_key unique(booking_id,author_id);

insert into public.reviews(booking_id,subject_id,author_id,rating,body,created_at)
select booking_id,renter_id,author_id,rating,body,created_at from public.renter_reviews
on conflict (booking_id,author_id) do nothing;

drop policy if exists renter_reviews_read on public.renter_reviews;
drop policy if exists renter_reviews_write on public.renter_reviews;
drop table if exists public.renter_reviews;

drop policy if exists reviews_write on public.reviews;
create policy reviews_write on public.reviews for insert to authenticated with check(
 author_id=auth.uid() and exists(
  select 1 from public.bookings b where b.id=booking_id
   and auth.uid() in (b.owner_id,b.renter_id)
   and subject_id=(case when b.owner_id=auth.uid() then b.renter_id else b.owner_id end)
 )
);

commit;
