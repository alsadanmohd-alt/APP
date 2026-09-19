-- Existing installations only. New installations use schema.sql instead.
-- Lets an owner opt in to publishing their item's exact coordinates (instead of the
-- rounded ~1km approximation) so anyone browsing sees the real distance immediately.
begin;

alter table public.items add column if not exists show_exact_location boolean not null default false;

drop function if exists public.create_item(text,text,text,numeric,text,text,double precision,double precision,text[]);
create function public.create_item(p_title text,p_description text,p_category text,p_price numeric,p_phone text,p_area text,p_lat double precision,p_lng double precision,p_images text[],p_show_exact boolean default false) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;
begin
 if auth.uid() is null then raise exception 'يلزم تسجيل الدخول'; end if;
 insert into items(owner_id,title,description,category,daily_price,contact_phone,area,lat,lng,images,show_exact_location) values(auth.uid(),p_title,p_description,p_category,p_price,p_phone,p_area,case when p_show_exact then p_lat else round(p_lat::numeric,2) end,case when p_show_exact then p_lng else round(p_lng::numeric,2) end,p_images,coalesce(p_show_exact,false)) returning id into v_id;
 insert into item_locations values(v_id,p_lat,p_lng); return v_id;
end $$;

drop function if exists public.update_item(uuid,text,text,text,numeric,text,text,double precision,double precision,text[]);
create function public.update_item(p_id uuid,p_title text,p_description text,p_category text,p_price numeric,p_phone text,p_area text,p_lat double precision,p_lng double precision,p_images text[] default null,p_show_exact boolean default null) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_show_exact boolean;
begin
 if auth.uid() is null then raise exception 'يلزم تسجيل الدخول'; end if;
 if not exists(select 1 from items where id=p_id and owner_id=auth.uid()) then raise exception 'غير مصرح'; end if;
 select coalesce(p_show_exact,show_exact_location) into v_show_exact from items where id=p_id;
 update items set title=p_title,description=p_description,category=p_category,daily_price=p_price,contact_phone=p_phone,area=p_area,lat=case when v_show_exact then p_lat else round(p_lat::numeric,2) end,lng=case when v_show_exact then p_lng else round(p_lng::numeric,2) end,images=coalesce(p_images,images),show_exact_location=v_show_exact where id=p_id;
 update item_locations set lat=p_lat,lng=p_lng where item_id=p_id;
end $$;

revoke all on function public.create_item(text,text,text,numeric,text,text,double precision,double precision,text[],boolean) from public;
revoke all on function public.update_item(uuid,text,text,text,numeric,text,text,double precision,double precision,text[],boolean) from public;
grant execute on function public.create_item(text,text,text,numeric,text,text,double precision,double precision,text[],boolean) to authenticated;
grant execute on function public.update_item(uuid,text,text,text,numeric,text,text,double precision,double precision,text[],boolean) to authenticated;

commit;
