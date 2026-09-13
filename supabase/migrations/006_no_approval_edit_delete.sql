-- Existing installations only. New installations use schema.sql instead.
-- Removes the request/accept/reject/cancel approval workflow entirely: a
-- "booking" row is now just an open contact thread, created the moment a
-- renter starts a conversation, with no owner approval step. Renter and
-- owner coordinate everything else directly by phone or chat. Also adds
-- item editing and deletion for owners.
begin;

update public.bookings set status='active' where status in ('pending','accepted','rejected','cancelled');
alter table public.bookings alter column status set default 'active';
alter table public.bookings drop constraint if exists bookings_status_check;
alter table public.bookings add constraint bookings_status_check check(status in ('active','completed'));

drop index if exists bookings_one_pending;
-- Note: this assumes no renter has more than one historical row per item under the
-- old workflow (true for a fresh/low-traffic project). If it fails, de-duplicate
-- bookings per (item_id, renter_id) first, keeping the most recent row.
create unique index if not exists bookings_one_per_renter on public.bookings(item_id,renter_id);

alter table public.bookings drop constraint if exists bookings_item_id_fkey;
alter table public.bookings add constraint bookings_item_id_fkey foreign key(item_id) references public.items(id) on delete cascade;
alter table public.messages drop constraint if exists messages_booking_id_fkey;
alter table public.messages add constraint messages_booking_id_fkey foreign key(booking_id) references public.bookings(id) on delete cascade;
alter table public.reviews drop constraint if exists reviews_booking_id_fkey;
alter table public.reviews add constraint reviews_booking_id_fkey foreign key(booking_id) references public.bookings(id) on delete cascade;

drop policy if exists messages_send on public.messages;
create policy messages_send on public.messages for insert to authenticated with check(sender_id=auth.uid() and exists(select 1 from public.bookings b where b.id=booking_id and auth.uid() in(b.owner_id,b.renter_id)));

drop policy if exists items_delete on public.items;
create policy items_delete on public.items for delete to authenticated using(owner_id=auth.uid());
grant delete on public.items to authenticated;

create function public.update_item(p_id uuid,p_title text,p_description text,p_category text,p_price numeric,p_phone text,p_area text,p_lat double precision,p_lng double precision,p_images text[] default null) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if auth.uid() is null then raise exception 'يلزم تسجيل الدخول'; end if;
 if not exists(select 1 from items where id=p_id and owner_id=auth.uid()) then raise exception 'غير مصرح'; end if;
 update items set title=p_title,description=p_description,category=p_category,daily_price=p_price,contact_phone=p_phone,area=p_area,lat=round(p_lat::numeric,2),lng=round(p_lng::numeric,2),images=coalesce(p_images,images) where id=p_id;
 update item_locations set lat=p_lat,lng=p_lng where item_id=p_id;
end $$;

create function public.get_owner_item_location(p_item uuid) returns table(lat double precision,lng double precision)
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if auth.uid() is null then raise exception 'يلزم تسجيل الدخول'; end if;
 if not exists(select 1 from items where id=p_item and owner_id=auth.uid()) then raise exception 'غير مصرح'; end if;
 return query select l.lat,l.lng from item_locations l where l.item_id=p_item;
end $$;

drop function if exists public.request_booking(uuid,date,date);
drop function if exists public.request_contact(uuid);
create function public.start_conversation(p_item uuid) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_item items%rowtype; v_id uuid;
begin
 if auth.uid() is null then raise exception 'يلزم تسجيل الدخول'; end if;
 select * into strict v_item from items where id=p_item;
 if v_item.owner_id=auth.uid() then raise exception 'لا يمكنك التواصل بخصوص غرضك'; end if;
 select id into v_id from bookings where item_id=p_item and renter_id=auth.uid();
 if v_id is null then
  insert into bookings(item_id,renter_id,owner_id) values(p_item,auth.uid(),v_item.owner_id) returning id into v_id;
 end if;
 return v_id;
end $$;

create or replace function public.get_pickup_distance(p_item uuid,p_lat double precision,p_lng double precision) returns numeric
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_item items%rowtype; v_loc item_locations%rowtype; v_allowed boolean;
begin
 if auth.uid() is null then raise exception 'يلزم تسجيل الدخول'; end if;
 select * into strict v_item from items where id=p_item;
 select * into v_loc from item_locations where item_id=p_item;
 if v_loc.item_id is null then raise exception 'الموقع غير متاح'; end if;
 v_allowed:=v_item.owner_id=auth.uid() or exists(select 1 from bookings b where b.item_id=p_item and b.renter_id=auth.uid());
 if not v_allowed then raise exception 'غير مصرح'; end if;
 return round((2*6371*asin(sqrt(sin(radians(v_loc.lat-p_lat)/2)^2+cos(radians(p_lat))*cos(radians(v_loc.lat))*sin(radians(v_loc.lng-p_lng)/2)^2)))::numeric,1);
end $$;

drop function if exists public.change_booking(uuid,text);
create function public.mark_completed(p_booking uuid) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare b bookings%rowtype;
begin
 select * into strict b from bookings where id=p_booking for update;
 if auth.uid() is null or auth.uid()<>b.owner_id then raise exception 'غير مصرح'; end if;
 if b.status<>'active' then raise exception 'لا يمكن تغيير حالة هذا التواصل'; end if;
 update bookings set status='completed' where id=b.id;
end $$;

revoke all on function public.update_item(uuid,text,text,text,numeric,text,text,double precision,double precision,text[]) from public;
revoke all on function public.get_owner_item_location(uuid) from public;
revoke all on function public.start_conversation(uuid) from public;
revoke all on function public.mark_completed(uuid) from public;
grant execute on function public.update_item(uuid,text,text,text,numeric,text,text,double precision,double precision,text[]) to authenticated;
grant execute on function public.get_owner_item_location(uuid) to authenticated;
grant execute on function public.start_conversation(uuid) to authenticated;
grant execute on function public.mark_completed(uuid) to authenticated;

commit;
