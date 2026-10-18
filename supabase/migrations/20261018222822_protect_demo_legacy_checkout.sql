CREATE OR REPLACE FUNCTION public.place_table_order(p_venue_slug text, p_table_id uuid, p_client_token uuid, p_items jsonb, p_customer_name text DEFAULT ''::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_venue public.venues%rowtype;
  v_existing uuid;
  v_line record;
  v_item public.menu_items%rowtype;
  v_order uuid;
  v_total bigint := 0;
  v_lines integer := 0;
begin
  if exists(select 1 from public.locations l join public.venues v on v.id=l.id where v.slug=p_venue_slug and l.demo_mode) then
    raise exception 'Use the demo checkout for this location';
  end if;
  select o.id into v_existing from public.orders o join public.venues v on v.id=o.venue_id
  where o.client_token=p_client_token and v.slug=p_venue_slug and o.table_id=p_table_id and o.order_kind='pay_at_venue';
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
$function$
;
revoke all on function public.place_table_order(text,uuid,uuid,jsonb,text) from public;
grant execute on function public.place_table_order(text,uuid,uuid,jsonb,text) to anon,authenticated;

