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
create table public.bookings (
 id uuid primary key default gen_random_uuid(), item_id uuid not null references public.items(id), renter_id uuid not null references auth.users(id), owner_id uuid not null references auth.users(id),
 status text not null default 'pending' check(status in ('pending','accepted','rejected','cancelled','completed')), created_at timestamptz not null default now(),
 check(owner_id<>renter_id)
);
create index bookings_participants on public.bookings(renter_id,owner_id);
create unique index bookings_one_pending on public.bookings(item_id,renter_id) where(status='pending');
create table public.messages(id uuid primary key default gen_random_uuid(),booking_id uuid not null references public.bookings(id),sender_id uuid not null references auth.users(id),body text not null check(char_length(trim(body)) between 1 and 2000),created_at timestamptz not null default now());
create index messages_booking on public.messages(booking_id,created_at);
create table public.reviews(id uuid primary key default gen_random_uuid(),booking_id uuid not null unique references public.bookings(id),item_id uuid not null references public.items(id),author_id uuid not null references auth.users(id),rating int not null check(rating between 1 and 5),body text not null check(char_length(trim(body)) between 1 and 1000),created_at timestamptz not null default now());
alter table public.items enable row level security;
alter table public.item_locations enable row level security;
alter table public.bookings enable row level security;
alter table public.messages enable row level security;
alter table public.reviews enable row level security;
create policy items_read on public.items for select using(true);
create policy bookings_read on public.bookings for select to authenticated using(auth.uid() in (owner_id,renter_id));
-- item_locations has no select policy at all: the exact address is never sent to any client.
-- Only get_pickup_distance() (security definer, bypasses RLS) may read it, and it returns a distance, not coordinates.
create policy messages_read on public.messages for select to authenticated using(exists(select 1 from public.bookings b where b.id=booking_id and auth.uid() in (b.owner_id,b.renter_id)));
create policy messages_send on public.messages for insert to authenticated with check(sender_id=auth.uid() and exists(select 1 from public.bookings b where b.id=booking_id and auth.uid() in(b.owner_id,b.renter_id) and b.status in ('pending','accepted','completed')));
create policy reviews_read on public.reviews for select using(true);
create policy reviews_write on public.reviews for insert to authenticated with check(author_id=auth.uid() and exists(select 1 from public.bookings b where b.id=booking_id and b.item_id=reviews.item_id and b.renter_id=auth.uid() and b.status='completed'));
-- Atomic creation: exact coordinates never enter public item rows.
create function public.create_item(p_title text,p_description text,p_category text,p_price numeric,p_phone text,p_area text,p_lat double precision,p_lng double precision,p_images text[]) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;
begin
 if auth.uid() is null then raise exception 'يلزم تسجيل الدخول'; end if;
 insert into items(owner_id,title,description,category,daily_price,contact_phone,area,lat,lng,images) values(auth.uid(),p_title,p_description,p_category,p_price,p_phone,p_area,round(p_lat::numeric,2),round(p_lng::numeric,2),p_images) returning id into v_id;
 insert into item_locations values(v_id,p_lat,p_lng); return v_id;
end $$;
-- Contact request: no dates or deposit. Renter and owner coordinate the rental period directly by phone or chat.
create function public.request_contact(p_item uuid) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_item items%rowtype;v_id uuid;
begin
 if auth.uid() is null then raise exception 'يلزم تسجيل الدخول'; end if;
 select * into strict v_item from items where id=p_item;
 if v_item.owner_id=auth.uid() then raise exception 'لا يمكنك التواصل بخصوص غرضك'; end if;
 insert into bookings(item_id,renter_id,owner_id) values(p_item,auth.uid(),v_item.owner_id) returning id into v_id;return v_id;
exception when unique_violation then raise exception 'لديك طلب قائم بالفعل لهذا الغرض';
end $$;
-- Returns only a distance in km, never the stored exact coordinates. The public
-- item row keeps an approximate location; this is the sole way to learn more,
-- and only for the owner or a renter with an accepted/completed request.
create function public.get_pickup_distance(p_item uuid,p_lat double precision,p_lng double precision) returns numeric
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_item items%rowtype; v_loc item_locations%rowtype; v_allowed boolean;
begin
 if auth.uid() is null then raise exception 'يلزم تسجيل الدخول'; end if;
 select * into strict v_item from items where id=p_item;
 select * into v_loc from item_locations where item_id=p_item;
 if v_loc.item_id is null then raise exception 'الموقع غير متاح'; end if;
 v_allowed:=v_item.owner_id=auth.uid() or exists(select 1 from bookings b where b.item_id=p_item and b.renter_id=auth.uid() and b.status in ('accepted','completed'));
 if not v_allowed then raise exception 'غير مصرح'; end if;
 return round((2*6371*asin(sqrt(sin(radians(v_loc.lat-p_lat)/2)^2+cos(radians(p_lat))*cos(radians(v_loc.lat))*sin(radians(v_loc.lng-p_lng)/2)^2)))::numeric,1);
end $$;
create function public.change_booking(p_booking uuid,p_status text) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare b bookings%rowtype;
begin
 select * into strict b from bookings where id=p_booking for update;
 if auth.uid() is null or auth.uid() not in(b.owner_id,b.renter_id) then raise exception 'غير مصرح'; end if;
 if p_status in ('accepted','rejected') and b.status='pending' and auth.uid()=b.owner_id then update bookings set status=p_status where id=b.id;
 elsif p_status='cancelled' and b.status='pending' and auth.uid()=b.renter_id then update bookings set status=p_status where id=b.id;
 elsif p_status='completed' and b.status='accepted' and auth.uid()=b.owner_id then update bookings set status=p_status where id=b.id;
 else raise exception 'لا يمكن تغيير حالة هذا الحجز'; end if;
end $$;
revoke all on function public.create_item(text,text,text,numeric,text,text,double precision,double precision,text[]) from public;
revoke all on function public.request_contact(uuid) from public;
revoke all on function public.change_booking(uuid,text) from public;
revoke all on function public.get_pickup_distance(uuid,double precision,double precision) from public;
grant execute on function public.create_item(text,text,text,numeric,text,text,double precision,double precision,text[]) to authenticated;
grant execute on function public.request_contact(uuid) to authenticated;
grant execute on function public.change_booking(uuid,text) to authenticated;
grant execute on function public.get_pickup_distance(uuid,double precision,double precision) to authenticated;
revoke all on public.items,public.item_locations,public.bookings,public.messages,public.reviews from anon,authenticated;
grant select on public.items,public.reviews to anon,authenticated;
grant select on public.bookings,public.messages to authenticated;
grant insert on public.messages,public.reviews to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('item-images','item-images',true,5242880,array['image/jpeg','image/png','image/webp']);
create policy images_upload on storage.objects for insert to authenticated with check(bucket_id='item-images' and (storage.foldername(name))[1]=auth.uid()::text);
-- Images are public. The browser re-encodes uploaded images to strip EXIF/GPS.
