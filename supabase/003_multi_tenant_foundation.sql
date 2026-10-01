-- Additive migration. Existing venue IDs remain the location IDs and all existing orders survive.
create table public.organisations (
 id uuid primary key default gen_random_uuid(),
 slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length(slug) between 3 and 40),
 name text not null check (length(trim(name)) between 2 and 120),
 created_at timestamptz not null default now()
);
create table public.organisation_members (
 organisation_id uuid not null references public.organisations(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 role text not null check (role in ('owner','admin','manager','staff')),
 created_at timestamptz not null default now(),
 primary key (organisation_id,user_id)
);
create index organisation_members_user_idx on public.organisation_members(user_id,organisation_id);
create table public.locations (
 id uuid primary key references public.venues(id) on delete cascade,
 organisation_id uuid not null references public.organisations(id) on delete cascade,
 slug text not null check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length(slug) between 2 and 40),
 name text not null check (length(trim(name)) between 2 and 120),
 logo_url text,
 primary_colour text not null default '#252629' check (primary_colour ~ '^#[0-9a-fA-F]{6}$'),
 accent_colour text not null default '#7206fd' check (accent_colour ~ '^#[0-9a-fA-F]{6}$'),
 demo_mode boolean not null default true,
 timezone text not null default 'Europe/London',
 created_at timestamptz not null default now(),
 unique(organisation_id,slug), unique(id,organisation_id)
);
create index locations_org_idx on public.locations(organisation_id);
create table public.location_domains (
 id uuid primary key default gen_random_uuid(),
 organisation_id uuid not null,
 location_id uuid not null,
 hostname text not null unique check (hostname = lower(hostname) and hostname !~ '[/: ]' and length(hostname) between 4 and 253),
 domain_type text not null default 'custom' check(domain_type in ('custom','platform')),
 verification_status text not null default 'pending' check(verification_status in ('pending','verified','failed')),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 foreign key(location_id,organisation_id) references public.locations(id,organisation_id) on delete cascade
);
create index location_domains_location_idx on public.location_domains(location_id);
create table public.preparation_stations (
 id uuid primary key default gen_random_uuid(),
 location_id uuid not null references public.locations(id) on delete cascade,
 name text not null check(length(trim(name)) between 1 and 60),
 active boolean not null default true,
 unique(id,location_id),unique(location_id,name)
);
alter table public.menu_items add column station_id uuid;
alter table public.menu_items add constraint menu_item_station_same_location foreign key(station_id,venue_id) references public.preparation_stations(id,location_id);
alter table public.menu_items add column visibility text not null default 'available' check(visibility in ('available','sold_out','hidden'));
alter table public.menu_items add column sort_order integer not null default 0;
alter table public.menu_items add column image_url text;
alter table public.menu_items add column dietary_info text not null default '';
alter table public.menu_items add column allergen_info text not null default '';
alter table public.venue_tables add column area text not null default 'Main';
alter table public.menu_items add constraint menu_items_id_venue_unique unique(id,venue_id);
create table public.modifier_groups (
 id uuid primary key default gen_random_uuid(),
 venue_id uuid not null references public.locations(id) on delete cascade,
 item_id uuid not null,
 foreign key(item_id,venue_id) references public.menu_items(id,venue_id) on delete cascade,
 name text not null check(length(trim(name)) between 1 and 80),
 min_choices integer not null default 0 check(min_choices between 0 and 20),
 max_choices integer not null default 1 check(max_choices between 1 and 20),
 sort_order integer not null default 0,
 check(min_choices<=max_choices),unique(id,venue_id)
);
create index modifier_groups_item_idx on public.modifier_groups(item_id,sort_order);
create table public.modifier_options (
 id uuid primary key default gen_random_uuid(),
 group_id uuid not null references public.modifier_groups(id) on delete cascade,
 name text not null check(length(trim(name)) between 1 and 80),
 price_delta_pence integer not null default 0 check(price_delta_pence between -100000 and 100000),
 available boolean not null default true,
 sort_order integer not null default 0
);
create index modifier_options_group_idx on public.modifier_options(group_id,sort_order);
alter table public.orders add column order_kind text not null default 'pay_at_venue' check(order_kind in ('demo','pay_at_venue','paid_online'));
alter table public.orders add column payment_status text not null default 'unpaid' check(payment_status in ('unpaid','demo_simulated','pending','paid','refunded'));
alter table public.order_items add column modifiers_snapshot jsonb not null default '[]'::jsonb;
alter table public.order_items add column station_id uuid references public.preparation_stations(id) on delete set null;

-- Migrate all existing venues, including any created since the first release.
insert into public.organisations(id,slug,name)
select id,slug,name from public.venues on conflict(id) do nothing;
insert into public.organisation_members(organisation_id,user_id,role)
select id,owner_user_id,'owner' from public.venues on conflict do nothing;
insert into public.locations(id,organisation_id,slug,name,timezone,demo_mode)
select id,id,slug,name,timezone,false from public.venues on conflict(id) do nothing;

alter table public.organisations enable row level security;
alter table public.organisation_members enable row level security;
alter table public.locations enable row level security;
alter table public.location_domains enable row level security;
alter table public.preparation_stations enable row level security;
alter table public.modifier_groups enable row level security;
alter table public.modifier_options enable row level security;

create policy org_member_read on public.organisations for select to authenticated using (
 exists(select 1 from public.organisation_members m where m.organisation_id=id and m.user_id=(select auth.uid())));
create policy member_self_read on public.organisation_members for select to authenticated using (user_id=(select auth.uid()));
create policy location_public_read on public.locations for select to anon,authenticated using (
 exists(select 1 from public.venues v where v.id=id and v.accepting_orders)
 or exists(select 1 from public.organisation_members m where m.organisation_id=organisation_id and m.user_id=(select auth.uid())));
create policy location_manager_update on public.locations for update to authenticated using (
 exists(select 1 from public.organisation_members m where m.organisation_id=organisation_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager')))
 with check(exists(select 1 from public.organisation_members m where m.organisation_id=organisation_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager')));
create policy domains_public_verified on public.location_domains for select to anon,authenticated using (
 verification_status='verified' or exists(select 1 from public.organisation_members m where m.organisation_id=organisation_id and m.user_id=(select auth.uid())));
create policy station_member_read on public.preparation_stations for select to authenticated using (
 exists(select 1 from public.locations l join public.organisation_members m on m.organisation_id=l.organisation_id where l.id=location_id and m.user_id=(select auth.uid())));
create policy station_manager_write on public.preparation_stations for all to authenticated using (
 exists(select 1 from public.locations l join public.organisation_members m on m.organisation_id=l.organisation_id where l.id=location_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager')))
 with check(exists(select 1 from public.locations l join public.organisation_members m on m.organisation_id=l.organisation_id where l.id=location_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager')));
create policy modifier_group_public_read on public.modifier_groups for select to anon,authenticated using (
 exists(select 1 from public.venues v where v.id=venue_id and v.accepting_orders) or exists(select 1 from public.locations l join public.organisation_members m on m.organisation_id=l.organisation_id where l.id=venue_id and m.user_id=(select auth.uid())));
create policy modifier_group_manager_write on public.modifier_groups for all to authenticated using (
 exists(select 1 from public.locations l join public.organisation_members m on m.organisation_id=l.organisation_id where l.id=venue_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager')))
 with check(exists(select 1 from public.locations l join public.organisation_members m on m.organisation_id=l.organisation_id where l.id=venue_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager')));
create policy modifier_option_public_read on public.modifier_options for select to anon,authenticated using (
 exists(select 1 from public.modifier_groups g join public.venues v on v.id=g.venue_id where g.id=group_id and v.accepting_orders)
 or exists(select 1 from public.modifier_groups g join public.locations l on l.id=g.venue_id join public.organisation_members m on m.organisation_id=l.organisation_id where g.id=group_id and m.user_id=(select auth.uid())));
create policy modifier_option_manager_write on public.modifier_options for all to authenticated using (
 exists(select 1 from public.modifier_groups g join public.locations l on l.id=g.venue_id join public.organisation_members m on m.organisation_id=l.organisation_id where g.id=group_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager')))
 with check(exists(select 1 from public.modifier_groups g join public.locations l on l.id=g.venue_id join public.organisation_members m on m.organisation_id=l.organisation_id where g.id=group_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager')));

-- Hidden products are private to venue staff even when a venue accepts orders.
drop policy items_read on public.menu_items;
create policy items_read on public.menu_items for select to anon,authenticated using (
 (visibility <> 'hidden' and exists(select 1 from public.venues v where v.id=venue_id and v.accepting_orders))
 or exists(select 1 from public.venues v where v.id=venue_id and v.owner_user_id=(select auth.uid())));

-- Preserve existing owner policies; extend scoped access for other organisation staff.
create policy venue_member_read on public.venues for select to authenticated using (
 exists(select 1 from public.locations l join public.organisation_members m on m.organisation_id=l.organisation_id where l.id=id and m.user_id=(select auth.uid())));
create policy categories_member_read on public.menu_categories for select to authenticated using (
 exists(select 1 from public.locations l join public.organisation_members m on m.organisation_id=l.organisation_id where l.id=venue_id and m.user_id=(select auth.uid())));
create policy items_member_read on public.menu_items for select to authenticated using (
 exists(select 1 from public.locations l join public.organisation_members m on m.organisation_id=l.organisation_id where l.id=venue_id and m.user_id=(select auth.uid())));
create policy tables_member_read on public.venue_tables for select to authenticated using (
 exists(select 1 from public.locations l join public.organisation_members m on m.organisation_id=l.organisation_id where l.id=venue_id and m.user_id=(select auth.uid())));
create policy orders_member_read on public.orders for select to authenticated using (
 exists(select 1 from public.locations l join public.organisation_members m on m.organisation_id=l.organisation_id where l.id=venue_id and m.user_id=(select auth.uid())));
create policy order_items_member_read on public.order_items for select to authenticated using (
 exists(select 1 from public.orders o join public.locations l on l.id=o.venue_id join public.organisation_members m on m.organisation_id=l.organisation_id where o.id=order_id and m.user_id=(select auth.uid())));

-- API access still requires RLS for each row.
grant select on public.locations,public.location_domains,public.modifier_groups,public.modifier_options to anon;
grant select on public.organisations,public.organisation_members,public.locations,public.location_domains,public.preparation_stations,public.modifier_groups,public.modifier_options to authenticated;
grant insert,update,delete on public.preparation_stations,public.modifier_groups,public.modifier_options to authenticated;
grant update(logo_url,primary_colour,accent_colour,demo_mode,name) on public.locations to authenticated;

-- Initial org creation is one transaction and never lets a caller choose someone else's owner ID.
create or replace function public.create_cuego_organisation(p_name text,p_slug text,p_location_name text,p_location_slug text)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=(select auth.uid()); v_org uuid; v_location uuid;
begin
 if v_user is null then raise exception 'Sign in first'; end if;
 if length(trim(p_name)) not between 2 and 120 or p_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then raise exception 'Invalid organisation'; end if;
 if length(trim(p_location_name)) not between 2 and 120 or p_location_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then raise exception 'Invalid location'; end if;
 insert into public.organisations(slug,name) values(p_slug,trim(p_name)) returning id into v_org;
 insert into public.organisation_members(organisation_id,user_id,role) values(v_org,v_user,'owner');
 insert into public.venues(owner_user_id,slug,name) values(v_user,p_slug||'-'||p_location_slug,trim(p_location_name)) returning id into v_location;
 insert into public.locations(id,organisation_id,slug,name) values(v_location,v_org,p_location_slug,trim(p_location_name));
 insert into public.preparation_stations(location_id,name) values(v_location,'Bar'),(v_location,'Kitchen');
 return v_location;
end;
$$;
revoke all on function public.create_cuego_organisation(text,text,text,text) from public;
grant execute on function public.create_cuego_organisation(text,text,text,text) to authenticated;
