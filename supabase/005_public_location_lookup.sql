-- Public location resolution returns only branding for active ordering locations.
create or replace function public.resolve_ordering_location(p_hostname text default null,p_organisation_slug text default null,p_location_slug text default null)
returns jsonb language sql stable security definer set search_path=''
as $$
 select jsonb_build_object('id',l.id,'organisation_id',o.id,'organisation_slug',o.slug,'location_slug',l.slug,
  'name',l.name,'logo_url',l.logo_url,'primary_colour',l.primary_colour,'accent_colour',l.accent_colour,
  'demo_mode',l.demo_mode,'hostname',d.hostname)
 from public.locations l join public.organisations o on o.id=l.organisation_id
 join public.venues v on v.id=l.id
 left join public.location_domains d on d.location_id=l.id and d.hostname=lower(trim(trailing '.' from coalesce(p_hostname,''))) and d.verification_status='verified'
 where v.accepting_orders=true and (
  (p_hostname is not null and d.id is not null)
  or (p_hostname is null and o.slug=p_organisation_slug and (l.slug=p_location_slug or (p_location_slug is null and (select count(*) from public.locations s where s.organisation_id=o.id)=1)))
 ) order by l.created_at limit 1;
$$;
revoke all on function public.resolve_ordering_location(text,text,text) from public;
grant execute on function public.resolve_ordering_location(text,text,text) to anon,authenticated;
