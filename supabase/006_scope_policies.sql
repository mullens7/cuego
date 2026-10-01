-- Qualify the outer row explicitly: unqualified names in a correlated policy can bind to the inner table.
drop policy venue_member_read on public.venues;
create policy venue_member_read on public.venues for select to authenticated using (
 exists(select 1 from public.locations l join public.organisation_members m on m.organisation_id=l.organisation_id where l.id=venues.id and m.user_id=(select auth.uid())));
drop policy location_public_read on public.locations;
create policy location_public_read on public.locations for select to anon,authenticated using (
 exists(select 1 from public.venues v where v.id=locations.id and v.accepting_orders)
 or exists(select 1 from public.organisation_members m where m.organisation_id=locations.organisation_id and m.user_id=(select auth.uid())));
drop policy location_manager_update on public.locations;
create policy location_manager_update on public.locations for update to authenticated using (
 exists(select 1 from public.organisation_members m where m.organisation_id=locations.organisation_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager')))
 with check(exists(select 1 from public.organisation_members m where m.organisation_id=locations.organisation_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager')));
drop policy domains_public_verified on public.location_domains;
create policy domains_public_verified on public.location_domains for select to anon,authenticated using (
 verification_status='verified' or exists(select 1 from public.organisation_members m where m.organisation_id=location_domains.organisation_id and m.user_id=(select auth.uid())));
-- Existing single-location permissions remain valid for owners; managers can operate any location in their organisation.
create policy venue_manager_update on public.venues for update to authenticated using (
 exists(select 1 from public.locations l join public.organisation_members m on m.organisation_id=l.organisation_id where l.id=venues.id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager')))
 with check(exists(select 1 from public.locations l join public.organisation_members m on m.organisation_id=l.organisation_id where l.id=venues.id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager')));
create policy categories_manager_write on public.menu_categories for all to authenticated using (
 exists(select 1 from public.locations l join public.organisation_members m on m.organisation_id=l.organisation_id where l.id=menu_categories.venue_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager')))
 with check(exists(select 1 from public.locations l join public.organisation_members m on m.organisation_id=l.organisation_id where l.id=menu_categories.venue_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager')));
create policy items_manager_write on public.menu_items for all to authenticated using (
 exists(select 1 from public.locations l join public.organisation_members m on m.organisation_id=l.organisation_id where l.id=menu_items.venue_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager')))
 with check(exists(select 1 from public.locations l join public.organisation_members m on m.organisation_id=l.organisation_id where l.id=menu_items.venue_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager')));
create policy tables_manager_write on public.venue_tables for all to authenticated using (
 exists(select 1 from public.locations l join public.organisation_members m on m.organisation_id=l.organisation_id where l.id=venue_tables.venue_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager')))
 with check(exists(select 1 from public.locations l join public.organisation_members m on m.organisation_id=l.organisation_id where l.id=venue_tables.venue_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager')));
-- Restrict direct updates to operational fields; clients cannot alter prices or payment state.
grant update(status,delivered_at) on public.orders to authenticated;
create policy orders_staff_update on public.orders for update to authenticated using (
 exists(select 1 from public.locations l join public.organisation_members m on m.organisation_id=l.organisation_id where l.id=orders.venue_id and m.user_id=(select auth.uid())))
 with check(exists(select 1 from public.locations l join public.organisation_members m on m.organisation_id=l.organisation_id where l.id=orders.venue_id and m.user_id=(select auth.uid())));
