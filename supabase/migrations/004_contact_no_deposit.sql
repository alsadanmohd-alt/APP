-- Existing installations only. New installations use schema.sql instead.
-- Removes the deposit/insurance concept and date-range bookings entirely.
-- Renter and owner now coordinate the rental period directly by phone or in-app chat.
begin;

alter table public.items drop column if exists deposit_amount;
alter table public.bookings drop column if exists deposit_amount;
alter table public.bookings drop column if exists starts_on;
alter table public.bookings drop column if exists ends_on;
alter table public.bookings drop column if exists total;

alter table public.items add column if not exists contact_phone text;
update public.items set contact_phone='+966500000000' where contact_phone is null;
-- Ask owners to update this placeholder to their real contact number after the migration.
alter table public.items alter column contact_phone set not null;
alter table public.items drop constraint if exists items_contact_phone_check;
alter table public.items add constraint items_contact_phone_check check(contact_phone ~ '^\+[1-9][0-9]{7,14}$');

create unique index if not exists bookings_one_pending on public.bookings(item_id,renter_id) where(status='pending');

alter table public.items drop constraint if exists items_category_check;
alter table public.items add constraint items_category_check
check(category in ('تصوير','رحلات','أدوات ومعدات','رياضة','منزل','إلكترونيات','تجهيز الحفلات','أدوات مطبخ'));

drop function if exists public.create_item(text,text,text,numeric,text,double precision,double precision,text[],numeric);
create function public.create_item(p_title text,p_description text,p_category text,p_price numeric,p_phone text,p_area text,p_lat double precision,p_lng double precision,p_images text[]) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;
begin
 if auth.uid() is null then raise exception 'يلزم تسجيل الدخول'; end if;
 insert into items(owner_id,title,description,category,daily_price,contact_phone,area,lat,lng,images) values(auth.uid(),p_title,p_description,p_category,p_price,p_phone,p_area,round(p_lat::numeric,2),round(p_lng::numeric,2),p_images) returning id into v_id;
 insert into item_locations values(v_id,p_lat,p_lng); return v_id;
end $$;

drop function if exists public.request_booking(uuid,date,date);
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

create or replace function public.change_booking(p_booking uuid,p_status text) returns void
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
grant execute on function public.create_item(text,text,text,numeric,text,text,double precision,double precision,text[]) to authenticated;
grant execute on function public.request_contact(uuid) to authenticated;

commit;
