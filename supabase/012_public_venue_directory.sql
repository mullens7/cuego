-- A narrow, public directory for guests arriving at the generic Cuego domain.
-- It never returns organisations whose location is not accepting orders.
create or replace function public.find_ordering_venues(p_query text)
returns table(name text, organisation_slug text, location_slug text)
language sql stable security definer set search_path = ''
as $$
  select l.name, o.slug, l.slug
  from public.locations l
  join public.organisations o on o.id = l.organisation_id
  join public.venues v on v.id = l.id
  where v.accepting_orders = true
    and length(trim(coalesce(p_query, ''))) between 2 and 80
    and (l.name ilike '%' || trim(p_query) || '%'
      or o.name ilike '%' || trim(p_query) || '%')
  order by l.name, o.slug, l.slug
  limit 12;
$$;
revoke all on function public.find_ordering_venues(text) from public, anon, authenticated;
grant execute on function public.find_ordering_venues(text) to anon, authenticated;
