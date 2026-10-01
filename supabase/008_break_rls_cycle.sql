-- A narrow helper avoids a locations -> venues -> locations RLS recursion.
create or replace function public.is_location_member(p_location_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$
 select exists(select 1 from public.locations l join public.organisation_members m on m.organisation_id=l.organisation_id
 where l.id=p_location_id and m.user_id=(select auth.uid()));
$$;
revoke all on function public.is_location_member(uuid) from public;
grant execute on function public.is_location_member(uuid) to authenticated;
drop policy venue_member_read on public.venues;
create policy venue_member_read on public.venues for select to authenticated using (public.is_location_member(venues.id));
