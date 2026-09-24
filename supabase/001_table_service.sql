-- Cuego table service: owner-managed venues, public menu, atomic guest orders.
create extension if not exists pgcrypto;

create table public.venues (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length(slug) between 3 and 40),
  name text not null check (length(trim(name)) between 2 and 100),
  accepting_orders boolean not null default false,
  created_at timestamptz not null default now()
);
create table public.menu_categories (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 80),
  sort_order integer not null default 0,
  unique (id, venue_id)
);
create table public.menu_items (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues(id) on delete cascade,
  category_id uuid,
  name text not null check (length(trim(name)) between 1 and 120),
  description text not null default '' check (length(description) <= 500),
  price_pence integer not null check (price_pence between 1 and 1000000),
  available boolean not null default true,
  stock_count integer check (stock_count is null or stock_count >= 0),
  created_at timestamptz not null default now(),
  foreign key (category_id, venue_id) references public.menu_categories(id, venue_id)
);
create table public.venue_tables (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues(id) on delete cascade,
  label text not null check (length(trim(label)) between 1 and 30),
  active boolean not null default true,
  unique (venue_id, label)
);
create table public.orders (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues(id) on delete cascade,
  table_id uuid not null references public.venue_tables(id),
  client_token uuid not null unique,
  status text not null default 'new' check (status in ('new','preparing','ready','delivered','cancelled')),
  customer_name text not null default '' check (length(customer_name) <= 80),
  total_pence integer not null check (total_pence > 0),
  created_at timestamptz not null default now(),
  delivered_at timestamptz
);
create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  item_id uuid references public.menu_items(id) on delete set null,
  name_snapshot text not null,
  price_pence integer not null,
  quantity integer not null check (quantity between 1 and 20)
);
create index on public.menu_categories (venue_id, sort_order);
create index on public.menu_items (venue_id, category_id);
create index on public.venue_tables (venue_id);
create index on public.orders (venue_id, created_at desc);
create index on public.order_items (order_id);

alter table public.venues enable row level security;
alter table public.menu_categories enable row level security;
alter table public.menu_items enable row level security;
alter table public.venue_tables enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;

create policy venues_read on public.venues for select to anon, authenticated
  using (accepting_orders or owner_user_id = (select auth.uid()));
create policy venues_create on public.venues for insert to authenticated
  with check (owner_user_id = (select auth.uid()));
create policy venues_edit on public.venues for update to authenticated
  using (owner_user_id = (select auth.uid())) with check (owner_user_id = (select auth.uid()));

create policy categories_read on public.menu_categories for select to anon, authenticated
  using (exists (select 1 from public.venues v where v.id = venue_id and (v.accepting_orders or v.owner_user_id = (select auth.uid()))));
create policy categories_create on public.menu_categories for insert to authenticated
  with check (exists (select 1 from public.venues v where v.id = venue_id and v.owner_user_id = (select auth.uid())));
create policy categories_edit on public.menu_categories for update to authenticated
  using (exists (select 1 from public.venues v where v.id = venue_id and v.owner_user_id = (select auth.uid())))
  with check (exists (select 1 from public.venues v where v.id = venue_id and v.owner_user_id = (select auth.uid())));
create policy categories_delete on public.menu_categories for delete to authenticated
  using (exists (select 1 from public.venues v where v.id = venue_id and v.owner_user_id = (select auth.uid())));

create policy items_read on public.menu_items for select to anon, authenticated
  using (exists (select 1 from public.venues v where v.id = venue_id and (v.accepting_orders or v.owner_user_id = (select auth.uid()))));
create policy items_create on public.menu_items for insert to authenticated
  with check (exists (select 1 from public.venues v where v.id = venue_id and v.owner_user_id = (select auth.uid())));
create policy items_edit on public.menu_items for update to authenticated
  using (exists (select 1 from public.venues v where v.id = venue_id and v.owner_user_id = (select auth.uid())))
  with check (exists (select 1 from public.venues v where v.id = venue_id and v.owner_user_id = (select auth.uid())));
create policy items_delete on public.menu_items for delete to authenticated
  using (exists (select 1 from public.venues v where v.id = venue_id and v.owner_user_id = (select auth.uid())));

create policy tables_read on public.venue_tables for select to anon, authenticated
  using (exists (select 1 from public.venues v where v.id = venue_id and (v.accepting_orders or v.owner_user_id = (select auth.uid()))));
create policy tables_create on public.venue_tables for insert to authenticated
  with check (exists (select 1 from public.venues v where v.id = venue_id and v.owner_user_id = (select auth.uid())));
create policy tables_edit on public.venue_tables for update to authenticated
  using (exists (select 1 from public.venues v where v.id = venue_id and v.owner_user_id = (select auth.uid())))
  with check (exists (select 1 from public.venues v where v.id = venue_id and v.owner_user_id = (select auth.uid())));
create policy tables_delete on public.venue_tables for delete to authenticated
  using (exists (select 1 from public.venues v where v.id = venue_id and v.owner_user_id = (select auth.uid())));

create policy orders_owner_read on public.orders for select to authenticated
  using (exists (select 1 from public.venues v where v.id = venue_id and v.owner_user_id = (select auth.uid())));
create policy orders_owner_update on public.orders for update to authenticated
  using (exists (select 1 from public.venues v where v.id = venue_id and v.owner_user_id = (select auth.uid())))
  with check (exists (select 1 from public.venues v where v.id = venue_id and v.owner_user_id = (select auth.uid())));
create policy order_items_owner_read on public.order_items for select to authenticated
  using (exists (select 1 from public.orders o join public.venues v on v.id = o.venue_id where o.id = order_id and v.owner_user_id = (select auth.uid())));

-- Public guests can submit only through this validated, transactional function.
create or replace function public.place_table_order(p_venue_slug text, p_table_id uuid, p_client_token uuid, p_items jsonb, p_customer_name text default '')
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_venue public.venues%rowtype;
  v_existing uuid;
  v_line record;
  v_item public.menu_items%rowtype;
  v_order uuid;
  v_total bigint := 0;
  v_lines integer := 0;
begin
  select id into v_existing from public.orders where client_token = p_client_token;
  if v_existing is not null then return v_existing; end if;
  if p_client_token is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) not between 1 and 30 then
    raise exception 'Invalid order';
  end if;
  if length(coalesce(p_customer_name,'')) > 80 then raise exception 'Name is too long'; end if;
  select * into v_venue from public.venues where slug = p_venue_slug and accepting_orders = true;
  if not found then raise exception 'This venue is not accepting orders'; end if;
  if not exists (select 1 from public.venue_tables where id = p_table_id and venue_id = v_venue.id and active = true) then
    raise exception 'Select a valid table';
  end if;
  -- Coalesce duplicate cart rows before locking inventory.
  for v_line in
    select (value->>'id')::uuid as item_id, sum((value->>'qty')::integer)::integer as qty
    from jsonb_array_elements(p_items) value
    group by (value->>'id')::uuid
    order by (value->>'id')::uuid
  loop
    if v_line.qty not between 1 and 20 then raise exception 'Invalid quantity'; end if;
    select * into v_item from public.menu_items where id = v_line.item_id and venue_id = v_venue.id for update;
    if not found or not v_item.available or (v_item.stock_count is not null and v_item.stock_count < v_line.qty) then
      raise exception 'An item is unavailable; refresh the menu';
    end if;
    v_total := v_total + v_item.price_pence::bigint * v_line.qty;
    v_lines := v_lines + 1;
  end loop;
  if v_lines = 0 or v_total > 10000000 then raise exception 'Invalid order total'; end if;
  insert into public.orders (venue_id,table_id,client_token,customer_name,total_pence)
  values (v_venue.id,p_table_id,p_client_token,trim(coalesce(p_customer_name,'')),v_total::integer) returning id into v_order;
  for v_line in
    select (value->>'id')::uuid as item_id, sum((value->>'qty')::integer)::integer as qty
    from jsonb_array_elements(p_items) value
    group by (value->>'id')::uuid
    order by (value->>'id')::uuid
  loop
    select * into v_item from public.menu_items where id = v_line.item_id;
    insert into public.order_items (order_id,item_id,name_snapshot,price_pence,quantity)
    values (v_order,v_item.id,v_item.name,v_item.price_pence,v_line.qty);
    if v_item.stock_count is not null then
      update public.menu_items set stock_count = stock_count - v_line.qty where id = v_item.id;
    end if;
  end loop;
  return v_order;
end;
$$;
revoke all on function public.place_table_order(text,uuid,uuid,jsonb,text) from public;
grant execute on function public.place_table_order(text,uuid,uuid,jsonb,text) to anon, authenticated;

-- Grant API table access separately from row policies; no public order table access.
grant select on public.venues, public.menu_categories, public.menu_items, public.venue_tables to anon;
grant select, insert, update, delete on public.venues, public.menu_categories, public.menu_items, public.venue_tables to authenticated;
grant select on public.orders to authenticated;
grant update (status, delivered_at) on public.orders to authenticated;
grant select on public.order_items to authenticated;
