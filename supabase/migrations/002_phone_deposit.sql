-- Existing installations only. New installations use schema.sql instead.
begin;
alter table public.items add column deposit_amount numeric(10,2) not null default 0 check(deposit_amount>=0 and deposit_amount<=100000);
alter table public.bookings add column deposit_amount numeric(10,2) not null default 0 check(deposit_amount>=0 and deposit_amount<=100000);
drop function public.create_item(text,text,text,numeric,text,double precision,double precision,text[]);
create or replace function public.create_item(p_title text,p_description text,p_category text,p_price numeric,p_area text,p_lat double precision,p_lng double precision,p_images text[],p_deposit numeric default 0) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;
begin
 if auth.uid() is null then raise exception 'يلزم تسجيل الدخول'; end if;
 insert into items(owner_id,title,description,category,daily_price,deposit_amount,area,lat,lng,images) values(auth.uid(),p_title,p_description,p_category,p_price,p_deposit,p_area,round(p_lat::numeric,2),round(p_lng::numeric,2),p_images) returning id into v_id;
 insert into item_locations values(v_id,p_lat,p_lng); return v_id;
end $$;
create or replace function public.request_booking(p_item uuid,p_start date,p_end date) returns uuid
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

revoke all on function public.create_item(text,text,text,numeric,text,double precision,double precision,text[],numeric) from public;
grant execute on function public.create_item(text,text,text,numeric,text,double precision,double precision,text[],numeric) to authenticated;
commit;
