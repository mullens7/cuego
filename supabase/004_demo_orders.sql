-- Demo orders are separate from real payment settlement. All prices are trusted DB snapshots.
alter table public.orders add column notes text not null default '' check(length(notes)<=500);
create table public.order_station_states (
 order_id uuid not null references public.orders(id) on delete cascade,
 station_id uuid not null references public.preparation_stations(id),
 status text not null default 'new' check(status in ('new','accepted','preparing','ready')),
 updated_at timestamptz not null default now(),
 primary key(order_id,station_id)
);
create index order_station_states_station_idx on public.order_station_states(station_id,status);
alter table public.order_station_states enable row level security;
create policy station_orders_read on public.order_station_states for select to authenticated using (
 exists(select 1 from public.orders o join public.locations l on l.id=o.venue_id join public.organisation_members m on m.organisation_id=l.organisation_id where o.id=order_id and m.user_id=(select auth.uid())));
create policy station_orders_update on public.order_station_states for update to authenticated using (
 exists(select 1 from public.orders o join public.locations l on l.id=o.venue_id join public.organisation_members m on m.organisation_id=l.organisation_id where o.id=order_id and m.user_id=(select auth.uid())))
 with check(exists(select 1 from public.orders o join public.locations l on l.id=o.venue_id join public.organisation_members m on m.organisation_id=l.organisation_id where o.id=order_id and m.user_id=(select auth.uid())));
grant select on public.order_station_states to authenticated;
grant update(status) on public.order_station_states to authenticated;

-- Include 'accepted' without changing older orders or old operator actions.
alter table public.orders drop constraint orders_status_check;
alter table public.orders add constraint orders_status_check check(status in ('new','accepted','preparing','ready','delivered','cancelled'));
create or replace function public.enforce_order_status()
returns trigger language plpgsql set search_path=''
as $$
declare v_line record;
begin
 if new.status<>old.status then
  if not ((old.status='new' and new.status in ('accepted','preparing','cancelled'))
   or (old.status='accepted' and new.status in ('preparing','cancelled'))
   or (old.status='preparing' and new.status in ('ready','cancelled'))
   or (old.status='ready' and new.status='delivered')) then raise exception 'Invalid order status change'; end if;
  if new.status='cancelled' then
   for v_line in select item_id,quantity from public.order_items where order_id=old.id and item_id is not null loop
    update public.menu_items set stock_count=stock_count+v_line.quantity where id=v_line.item_id and stock_count is not null;
   end loop;
  end if;
  new.delivered_at=case when new.status='delivered' then now() else null end;
 end if;
 return new;
end;
$$;
create or replace function public.advance_station_state()
returns trigger language plpgsql set search_path=''
as $$
declare v_next text;v_current text;
begin
 if new.status=old.status then return new; end if;
 if not ((old.status='new' and new.status='accepted') or (old.status='accepted' and new.status='preparing') or (old.status='preparing' and new.status='ready')) then
  raise exception 'Invalid station status change';
 end if;
 new.updated_at=now();
 return new;
end;
$$;
create trigger station_state_guard before update on public.order_station_states for each row execute function public.advance_station_state();
create or replace function public.sync_order_progress()
returns trigger language plpgsql set search_path=''
as $$
declare v_target text;v_current text;
begin
 select case when bool_and(status='ready') then 'ready'
             when bool_or(status in ('preparing','ready')) then 'preparing'
             when bool_or(status='accepted') then 'accepted'
             else 'new' end into v_target
 from public.order_station_states where order_id=new.order_id;
 select status into v_current from public.orders where id=new.order_id for update;
 if v_current not in ('cancelled','delivered') and v_target<>v_current then
  update public.orders set status=v_target where id=new.order_id;
 end if;
 return null;
end;
$$;
create trigger station_state_sync after update of status on public.order_station_states for each row execute function public.sync_order_progress();

create or replace function public.place_demo_order(p_location_id uuid,p_table_id uuid,p_client_token uuid,p_lines jsonb,p_customer_name text default '',p_notes text default '')
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_location public.locations%rowtype; v_venue public.venues%rowtype; v_line jsonb;v_item public.menu_items%rowtype;
 v_group public.modifier_groups%rowtype;v_option public.modifier_options%rowtype;v_selected jsonb;v_option_id uuid;
 v_snapshot jsonb;v_qty integer;v_price bigint;v_total bigint:=0;v_order uuid;v_existing public.orders%rowtype;v_station uuid;v_n integer;
begin
 if p_client_token is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines) not between 1 and 30 then raise exception 'Invalid order'; end if;
 if length(coalesce(p_customer_name,''))>80 or length(coalesce(p_notes,''))>500 then raise exception 'Order notes are too long'; end if;
 select * into v_location from public.locations where id=p_location_id and demo_mode=true;
 if not found then raise exception 'Demo ordering unavailable'; end if;
 select * into v_venue from public.venues where id=p_location_id and accepting_orders=true;
 if not found then raise exception 'Location is not accepting orders'; end if;
 if not exists(select 1 from public.venue_tables where id=p_table_id and venue_id=p_location_id and active) then raise exception 'Invalid table'; end if;
 select * into v_existing from public.orders where client_token=p_client_token;
 if found then
  if v_existing.venue_id=p_location_id and v_existing.table_id=p_table_id and v_existing.order_kind='demo' then return v_existing.id; end if;
  raise exception 'Invalid order token';
 end if;
 -- Lock all affected product rows in a fixed order to serialize stock decisions.
 perform 1 from public.menu_items where id in (select (x->>'item_id')::uuid from jsonb_array_elements(p_lines) x) order by id for update;
 for v_line in select value from jsonb_array_elements(p_lines) loop
  v_qty=(v_line->>'quantity')::integer;
  if v_qty not between 1 and 20 then raise exception 'Invalid quantity'; end if;
  select * into v_item from public.menu_items where id=(v_line->>'item_id')::uuid and venue_id=p_location_id;
  if not found or not v_item.available or v_item.visibility<>'available' then raise exception 'An item is unavailable'; end if;
  v_selected=coalesce(v_line->'option_ids','[]'::jsonb);
  if jsonb_typeof(v_selected)<>'array' or jsonb_array_length(v_selected)>30 then raise exception 'Invalid selection'; end if;
  v_price=v_item.price_pence;v_snapshot='[]'::jsonb;
  for v_group in select * from public.modifier_groups where item_id=v_item.id order by sort_order,id loop
   select count(*) into v_n from jsonb_array_elements_text(v_selected) choice
    join public.modifier_options o on o.id=choice::uuid and o.group_id=v_group.id;
   if v_n not between v_group.min_choices and v_group.max_choices then raise exception 'Complete the product selections'; end if;
  end loop;
  if (select count(*) from jsonb_array_elements_text(v_selected))<>(select count(distinct value) from jsonb_array_elements_text(v_selected)) then raise exception 'Duplicate option'; end if;
  for v_option_id in select value::uuid from jsonb_array_elements_text(v_selected) loop
   select o.* into v_option from public.modifier_options o join public.modifier_groups g on g.id=o.group_id where o.id=v_option_id and g.item_id=v_item.id and o.available;
   if not found then raise exception 'An option is unavailable'; end if;
   v_price=v_price+v_option.price_delta_pence;
   v_snapshot=v_snapshot||jsonb_build_array(jsonb_build_object('option_id',v_option.id,'name',v_option.name,'price_delta_pence',v_option.price_delta_pence));
  end loop;
  if v_price<1 or v_price>1000000 then raise exception 'Invalid item price'; end if;
  v_total=v_total+v_price*v_qty;
 end loop;
 if v_total<1 or v_total>10000000 then raise exception 'Invalid order total'; end if;
 for v_item in select i.* from public.menu_items i where i.id in (select (x->>'item_id')::uuid from jsonb_array_elements(p_lines) x) loop
  if v_item.stock_count is not null and v_item.stock_count < (select sum((x->>'quantity')::integer) from jsonb_array_elements(p_lines) x where (x->>'item_id')::uuid=v_item.id) then raise exception 'An item has sold out'; end if;
 end loop;
 insert into public.orders(venue_id,table_id,client_token,customer_name,notes,total_pence,order_kind,payment_status)
 values(p_location_id,p_table_id,p_client_token,trim(coalesce(p_customer_name,'')),trim(coalesce(p_notes,'')),v_total::integer,'demo','demo_simulated') returning id into v_order;
 for v_line in select value from jsonb_array_elements(p_lines) loop
  select * into v_item from public.menu_items where id=(v_line->>'item_id')::uuid;
  v_qty=(v_line->>'quantity')::integer;v_price=v_item.price_pence;v_snapshot='[]'::jsonb;
  for v_option_id in select value::uuid from jsonb_array_elements_text(coalesce(v_line->'option_ids','[]'::jsonb)) loop
   select * into v_option from public.modifier_options where id=v_option_id;
   v_price=v_price+v_option.price_delta_pence;
   v_snapshot=v_snapshot||jsonb_build_array(jsonb_build_object('option_id',v_option.id,'name',v_option.name,'price_delta_pence',v_option.price_delta_pence));
  end loop;
  select coalesce(v_item.station_id,(select id from public.preparation_stations where location_id=p_location_id and active order by name limit 1)) into v_station;
  if v_station is null then raise exception 'No preparation station is configured'; end if;
  insert into public.order_items(order_id,item_id,name_snapshot,price_pence,quantity,modifiers_snapshot,station_id)
   values(v_order,v_item.id,v_item.name,v_price::integer,v_qty,v_snapshot,v_station);
  if v_item.stock_count is not null then update public.menu_items set stock_count=stock_count-v_qty where id=v_item.id; end if;
 end loop;
 insert into public.order_station_states(order_id,station_id)
 select distinct v_order,station_id from public.order_items where order_id=v_order;
 return v_order;
end;
$$;
revoke all on function public.place_demo_order(uuid,uuid,uuid,jsonb,text,text) from public;
grant execute on function public.place_demo_order(uuid,uuid,uuid,jsonb,text,text) to anon,authenticated;

create or replace function public.get_demo_order(p_order_id uuid,p_client_token uuid)
returns jsonb language sql stable security definer set search_path=''
as $$
 select jsonb_build_object('id',o.id,'status',o.status,'table',t.label,'location',l.name,'total_pence',o.total_pence,'kind',o.order_kind,
 'items',coalesce((select jsonb_agg(jsonb_build_object('name',i.name_snapshot,'quantity',i.quantity,'price_pence',i.price_pence,'modifiers',i.modifiers_snapshot)) from public.order_items i where i.order_id=o.id),'[]'::jsonb))
 from public.orders o join public.venue_tables t on t.id=o.table_id join public.locations l on l.id=o.venue_id
 where o.id=p_order_id and o.client_token=p_client_token and o.order_kind='demo';
$$;
revoke all on function public.get_demo_order(uuid,uuid) from public;
grant execute on function public.get_demo_order(uuid,uuid) to anon,authenticated;
