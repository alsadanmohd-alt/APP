-- Run once in a new Supabase project, using SQL Editor.
create extension if not exists btree_gist;
create table public.items (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id),
 title text not null check(char_length(title) between 3 and 100), description text not null check(char_length(description) between 10 and 3000),
 category text not null check(category in ('تصوير','رحلات','أدوات ومعدات','رياضة','منزل','إلكترونيات','تجهيز الحفلات')),
 deposit_amount numeric(10,2) not null default 0 check(deposit_amount>=0 and deposit_amount<=100000),
 daily_price numeric(10,2) not null check(daily_price>0 and daily_price<=100000), area text not null check(char_length(area) between 2 and 100),
 lat double precision not null check(lat between -90 and 90), lng double precision not null check(lng between -180 and 180),
 images text[] not null default '{}', created_at timestamptz not null default now(), check(cardinality(images)<=5)
);
create table public.item_locations(item_id uuid primary key references public.items(id) on delete cascade,lat double precision not null check(lat between -90 and 90),lng double precision not null check(lng between -180 and 180));
create table public.bookings (
 id uuid primary key default gen_random_uuid(), item_id uuid not null references public.items(id), renter_id uuid not null references auth.users(id), owner_id uuid not null references auth.users(id),
 deposit_amount numeric(10,2) not null default 0 check(deposit_amount>=0 and deposit_amount<=100000),
 starts_on date not null, ends_on date not null, total numeric(12,2) not null check(total>0),
 status text not null default 'pending' check(status in ('pending','accepted','rejected','cancelled','completed')), created_at timestamptz not null default now(),
 check(ends_on>starts_on),check(owner_id<>renter_id),
 exclude using gist(item_id with =,daterange(starts_on,ends_on,'[)') with &&) where(status in ('accepted','completed'))
);
create index bookings_participants on public.bookings(renter_id,owner_id);
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
create policy locations_read on public.item_locations for select to authenticated using(
 exists(select 1 from public.items i where i.id=item_id and i.owner_id=auth.uid()) or
 exists(select 1 from public.bookings b where b.item_id=item_locations.item_id and b.renter_id=auth.uid() and b.status in ('accepted','completed')));
create policy messages_read on public.messages for select to authenticated using(exists(select 1 from public.bookings b where b.id=booking_id and auth.uid() in (b.owner_id,b.renter_id)));
create policy messages_send on public.messages for insert to authenticated with check(sender_id=auth.uid() and exists(select 1 from public.bookings b where b.id=booking_id and auth.uid() in(b.owner_id,b.renter_id) and b.status in ('pending','accepted','completed')));
create policy reviews_read on public.reviews for select using(true);
create policy reviews_write on public.reviews for insert to authenticated with check(author_id=auth.uid() and exists(select 1 from public.bookings b where b.id=booking_id and b.item_id=reviews.item_id and b.renter_id=auth.uid() and b.status='completed'));
-- Atomic creation: exact coordinates never enter public item rows.
create function public.create_item(p_title text,p_description text,p_category text,p_price numeric,p_area text,p_lat double precision,p_lng double precision,p_images text[],p_deposit numeric default 0) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;
begin
 if auth.uid() is null then raise exception 'يلزم تسجيل الدخول'; end if;
 insert into items(owner_id,title,description,category,daily_price,deposit_amount,area,lat,lng,images) values(auth.uid(),p_title,p_description,p_category,p_price,p_deposit,p_area,round(p_lat::numeric,2),round(p_lng::numeric,2),p_images) returning id into v_id;
 insert into item_locations values(v_id,p_lat,p_lng); return v_id;
end $$;
create function public.request_booking(p_item uuid,p_start date,p_end date) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_item items%rowtype;v_id uuid;
begin
 if auth.uid() is null then raise exception 'يلزم تسجيل الدخول'; end if;
 if p_start is null or p_end is null or p_start<current_date or p_end<=p_start or p_end-p_start>90 then raise exception 'اختر مدة من يوم إلى 90 يوماً تبدأ اليوم أو لاحقاً'; end if;
 select * into strict v_item from items where id=p_item;
 if v_item.owner_id=auth.uid() then raise exception 'لا يمكنك حجز غرضك'; end if;
 if exists(select 1 from bookings where item_id=p_item and status in ('accepted','completed') and daterange(starts_on,ends_on,'[)') && daterange(p_start,p_end,'[)')) then raise exception 'الغرض محجوز خلال هذه المدة'; end if;
 if exists(select 1 from bookings where item_id=p_item and renter_id=auth.uid() and status='pending' and starts_on=p_start and ends_on=p_end) then raise exception 'لديك طلب قائم لهذه المدة'; end if;
 insert into bookings(item_id,renter_id,owner_id,starts_on,ends_on,total,deposit_amount) values(p_item,auth.uid(),v_item.owner_id,p_start,p_end,(p_end-p_start)*v_item.daily_price,v_item.deposit_amount) returning id into v_id;return v_id;
end $$;
create function public.change_booking(p_booking uuid,p_status text) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare b bookings%rowtype;
begin
 select * into strict b from bookings where id=p_booking for update;
 if auth.uid() is null or auth.uid() not in(b.owner_id,b.renter_id) then raise exception 'غير مصرح'; end if;
 if p_status in ('accepted','rejected') and b.status='pending' and auth.uid()=b.owner_id then
   if p_status='accepted' and b.starts_on<current_date then raise exception 'انتهى تاريخ بدء الطلب'; end if;
   update bookings set status=p_status where id=b.id;
 elsif p_status='cancelled' and b.status='pending' and auth.uid()=b.renter_id then update bookings set status=p_status where id=b.id;
 elsif p_status='completed' and b.status='accepted' and auth.uid()=b.owner_id and b.ends_on<=current_date then update bookings set status=p_status where id=b.id;
 else raise exception 'لا يمكن تغيير حالة هذا الحجز'; end if;
exception when exclusion_violation then raise exception 'يوجد حجز مؤكد يتداخل مع هذه الفترة';
end $$;
revoke all on function public.create_item(text,text,text,numeric,text,double precision,double precision,text[],numeric) from public;
revoke all on function public.request_booking(uuid,date,date) from public;
revoke all on function public.change_booking(uuid,text) from public;
grant execute on function public.create_item(text,text,text,numeric,text,double precision,double precision,text[],numeric) to authenticated;
grant execute on function public.request_booking(uuid,date,date) to authenticated;
grant execute on function public.change_booking(uuid,text) to authenticated;
revoke all on public.items,public.item_locations,public.bookings,public.messages,public.reviews from anon,authenticated;
grant select on public.items,public.reviews to anon,authenticated;
grant select on public.item_locations,public.bookings,public.messages to authenticated;
grant insert on public.messages,public.reviews to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('item-images','item-images',true,5242880,array['image/jpeg','image/png','image/webp']);
create policy images_upload on storage.objects for insert to authenticated with check(bucket_id='item-images' and (storage.foldername(name))[1]=auth.uid()::text);
-- Images are public. The browser re-encodes uploaded images to strip EXIF/GPS.
