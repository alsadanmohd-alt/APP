-- Existing installations only. New installations use schema.sql instead.
-- Adds a catch-all "أخرى" category, and replaces the exact-location reveal
-- with a distance-only lookup: the renter now sees the real distance to the
-- owner instead of the owner's exact pickup coordinates.
begin;

alter table public.items drop constraint if exists items_category_check;
alter table public.items add constraint items_category_check
check(category in ('تصوير','رحلات','أدوات ومعدات','رياضة','منزل','إلكترونيات','تجهيز الحفلات','أدوات مطبخ','أخرى'));

drop policy if exists locations_read on public.item_locations;
revoke select on public.item_locations from authenticated;
-- item_locations now has no select policy at all: the exact address is never
-- sent to any client. Only get_pickup_distance() (security definer, bypasses
-- RLS) may read it, and it returns a distance, not coordinates.

create or replace function public.get_pickup_distance(p_item uuid,p_lat double precision,p_lng double precision) returns numeric
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

revoke all on function public.get_pickup_distance(uuid,double precision,double precision) from public;
grant execute on function public.get_pickup_distance(uuid,double precision,double precision) to authenticated;

commit;
