-- Existing installations only. New installations use schema.sql instead.
-- Lets an owner bump their item's created_at to now(), so it reads as freshly
-- posted again (top of the "nearest" sort, "posted just now" badge).
begin;

create or replace function public.renew_item(p_id uuid) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if auth.uid() is null then raise exception 'يلزم تسجيل الدخول'; end if;
 if not exists(select 1 from items where id=p_id and owner_id=auth.uid()) then raise exception 'غير مصرح'; end if;
 update items set created_at=now() where id=p_id;
end $$;

revoke all on function public.renew_item(uuid) from public;
grant execute on function public.renew_item(uuid) to authenticated;

commit;
