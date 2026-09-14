-- Run once in a new Supabase project, using SQL Editor.
create table public.items (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id),
 title text not null check(char_length(title) between 3 and 100), description text not null check(char_length(description) between 10 and 3000),
 category text not null check(category in ('تصوير','رحلات','أدوات ومعدات','رياضة','منزل','إلكترونيات','تجهيز الحفلات','أدوات مطبخ','أخرى')),
 contact_phone text not null check(contact_phone ~ '^\+[1-9][0-9]{7,14}$'),
 daily_price numeric(10,2) not null check(daily_price>0 and daily_price<=100000), area text not null check(char_length(area) between 2 and 100),
 lat double precision not null check(lat between -90 and 90), lng double precision not null check(lng between -180 and 180),
 images text[] not null default '{}', created_at timestamptz not null default now(), check(cardinality(images)<=5)
);
create table public.item_locations(item_id uuid primary key references public.items(id) on delete cascade,lat double precision not null check(lat between -90 and 90),lng double precision not null check(lng between -180 and 180));
-- No approval step: a "booking" row is just an open contact thread between a
-- renter and an owner about an item. Renter and owner coordinate everything
-- else (dates, price, handover) directly by phone or chat.
create table public.bookings (
 id uuid primary key default gen_random_uuid(), item_id uuid not null references public.items(id) on delete cascade, renter_id uuid not null references auth.users(id), owner_id uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 check(owner_id<>renter_id)
);
create index bookings_participants on public.bookings(renter_id,owner_id);
create unique index bookings_one_per_renter on public.bookings(item_id,renter_id);
create table public.messages(id uuid primary key default gen_random_uuid(),booking_id uuid not null references public.bookings(id) on delete cascade,sender_id uuid not null references auth.users(id),body text not null check(char_length(trim(body)) between 1 and 2000),created_at timestamptz not null default now());
create index messages_booking on public.messages(booking_id,created_at);
create table public.reviews(id uuid primary key default gen_random_uuid(),booking_id uuid not null unique references public.bookings(id) on delete cascade,item_id uuid not null references public.items(id),author_id uuid not null references auth.users(id),rating int not null check(rating between 1 and 5),body text not null check(char_length(trim(body)) between 1 and 1000),created_at timestamptz not null default now());
alter table public.items enable row level security;
alter table public.item_locations enable row level security;
alter table public.bookings enable row level security;
alter table public.messages enable row level security;
alter table public.reviews enable row level security;
create policy items_read on public.items for select using(true);
create policy items_delete on public.items for delete to authenticated using(owner_id=auth.uid());
create policy bookings_read on public.bookings for select to authenticated using(auth.uid() in (owner_id,renter_id));
-- item_locations has no select policy at all: the exact address is never sent to any client.
-- Only get_pickup_distance() and get_owner_item_location() (security definer, bypass RLS) may
-- read it: the first returns a distance to a renter, the second returns coordinates but only
-- to the item's own owner (for editing), never to anyone else.
create policy messages_read on public.messages for select to authenticated using(exists(select 1 from public.bookings b where b.id=booking_id and auth.uid() in (b.owner_id,b.renter_id)));
create policy messages_send on public.messages for insert to authenticated with check(sender_id=auth.uid() and exists(select 1 from public.bookings b where b.id=booking_id and auth.uid() in(b.owner_id,b.renter_id)));
create policy reviews_read on public.reviews for select using(true);
create policy reviews_write on public.reviews for insert to authenticated with check(author_id=auth.uid() and exists(select 1 from public.bookings b where b.id=booking_id and b.item_id=reviews.item_id and b.renter_id=auth.uid()));
-- Atomic creation: exact coordinates never enter public item rows.
create function public.create_item(p_title text,p_description text,p_category text,p_price numeric,p_phone text,p_area text,p_lat double precision,p_lng double precision,p_images text[]) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;
begin
 if auth.uid() is null then raise exception 'يلزم تسجيل الدخول'; end if;
 insert into items(owner_id,title,description,category,daily_price,contact_phone,area,lat,lng,images) values(auth.uid(),p_title,p_description,p_category,p_price,p_phone,p_area,round(p_lat::numeric,2),round(p_lng::numeric,2),p_images) returning id into v_id;
 insert into item_locations values(v_id,p_lat,p_lng); return v_id;
end $$;
-- p_images null keeps the item's existing photos unchanged; pass a full array to replace them.
create function public.update_item(p_id uuid,p_title text,p_description text,p_category text,p_price numeric,p_phone text,p_area text,p_lat double precision,p_lng double precision,p_images text[] default null) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if auth.uid() is null then raise exception 'يلزم تسجيل الدخول'; end if;
 if not exists(select 1 from items where id=p_id and owner_id=auth.uid()) then raise exception 'غير مصرح'; end if;
 update items set title=p_title,description=p_description,category=p_category,daily_price=p_price,contact_phone=p_phone,area=p_area,lat=round(p_lat::numeric,2),lng=round(p_lng::numeric,2),images=coalesce(p_images,images) where id=p_id;
 update item_locations set lat=p_lat,lng=p_lng where item_id=p_id;
end $$;
-- Lets an owner see their own item's exact pickup point again when editing it. Never callable for anyone else's item.
create function public.get_owner_item_location(p_item uuid) returns table(lat double precision,lng double precision)
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if auth.uid() is null then raise exception 'يلزم تسجيل الدخول'; end if;
 if not exists(select 1 from items where id=p_item and owner_id=auth.uid()) then raise exception 'غير مصرح'; end if;
 return query select l.lat,l.lng from item_locations l where l.item_id=p_item;
end $$;
-- Starts (or returns the existing) contact thread for this renter and item. No approval needed:
-- the renter can message or call the owner immediately.
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
-- Returns only a distance in km, never the stored exact coordinates. The public
-- item row keeps an approximate location; this is the sole way to learn more,
-- and only for the item's owner or a renter who has started a conversation about it.
create function public.get_pickup_distance(p_item uuid,p_lat double precision,p_lng double precision) returns numeric
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
revoke all on function public.create_item(text,text,text,numeric,text,text,double precision,double precision,text[]) from public;
revoke all on function public.update_item(uuid,text,text,text,numeric,text,text,double precision,double precision,text[]) from public;
revoke all on function public.get_owner_item_location(uuid) from public;
revoke all on function public.start_conversation(uuid) from public;
revoke all on function public.get_pickup_distance(uuid,double precision,double precision) from public;
grant execute on function public.create_item(text,text,text,numeric,text,text,double precision,double precision,text[]) to authenticated;
grant execute on function public.update_item(uuid,text,text,text,numeric,text,text,double precision,double precision,text[]) to authenticated;
grant execute on function public.get_owner_item_location(uuid) to authenticated;
grant execute on function public.start_conversation(uuid) to authenticated;
grant execute on function public.get_pickup_distance(uuid,double precision,double precision) to authenticated;
revoke all on public.items,public.item_locations,public.bookings,public.messages,public.reviews from anon,authenticated;
grant select on public.items,public.reviews to anon,authenticated;
grant select on public.bookings,public.messages to authenticated;
grant delete on public.items to authenticated;
grant insert on public.messages,public.reviews to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('item-images','item-images',true,5242880,array['image/jpeg','image/png','image/webp']);
create policy images_upload on storage.objects for insert to authenticated with check(bucket_id='item-images' and (storage.foldername(name))[1]=auth.uid()::text);
-- Images are public. The browser re-encodes uploaded images to strip EXIF/GPS.
