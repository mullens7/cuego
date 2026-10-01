-- Aggregate only orders belonging to a location the caller belongs to.
create or replace function public.venue_order_stats(p_venue_id uuid)
returns jsonb language sql stable set search_path=''
as $$
 select jsonb_build_object(
  'today_count',count(*) filter(where (o.created_at at time zone v.timezone)::date=(now() at time zone v.timezone)::date and o.status<>'cancelled'),
  'today_pence',coalesce(sum(o.total_pence) filter(where (o.created_at at time zone v.timezone)::date=(now() at time zone v.timezone)::date and o.status<>'cancelled'),0),
  'week_count',count(*) filter(where (o.created_at at time zone v.timezone)::date>=(now() at time zone v.timezone)::date-6 and o.status<>'cancelled'),
  'week_pence',coalesce(sum(o.total_pence) filter(where (o.created_at at time zone v.timezone)::date>=(now() at time zone v.timezone)::date-6 and o.status<>'cancelled'),0))
 from public.venues v left join public.orders o on o.venue_id=v.id
 where v.id=p_venue_id and exists(select 1 from public.locations l join public.organisation_members m on m.organisation_id=l.organisation_id where l.id=v.id and m.user_id=(select auth.uid())) group by v.id;
$$;
