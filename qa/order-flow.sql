-- Run as postgres via Supabase SQL editor. All test changes are rolled back.
begin;
create temp table cuego_checks(name text,result text);
grant select,insert on cuego_checks to anon,authenticated;
select set_config('cuego.test.owner',(select user_id::text from cuego_private.platform_admins limit 1),true);
select set_config('cuego.test.location',(select id::text from public.locations where name='The Victory Inn'),true);
select set_config('cuego.test.table',(select id::text from public.venue_tables where venue_id=current_setting('cuego.test.location')::uuid and label='12'),true);
select set_config('cuego.test.token',gen_random_uuid()::text,true);
select set_config('cuego.test.lines',jsonb_build_array(
 jsonb_build_object('item_id',(select id from public.menu_items where venue_id=current_setting('cuego.test.location')::uuid and name='Heineken'),'quantity',2,'price_pence',1,'option_ids',jsonb_build_array((select o.id from public.modifier_options o join public.modifier_groups g on g.id=o.group_id join public.menu_items i on i.id=g.item_id where i.venue_id=current_setting('cuego.test.location')::uuid and i.name='Heineken' and o.name='Pint'))),
 jsonb_build_object('item_id',(select id from public.menu_items where venue_id=current_setting('cuego.test.location')::uuid and name='The Victory'),'quantity',1,'option_ids','[]'::jsonb)
)::text,true);
set local role anon;
select set_config('cuego.test.order',public.place_demo_order(current_setting('cuego.test.location')::uuid,current_setting('cuego.test.table')::uuid,current_setting('cuego.test.token')::uuid,current_setting('cuego.test.lines')::jsonb,'','QA rollback test')::text,true);
insert into pg_temp.cuego_checks select 'trusted_total', (public.get_demo_order(current_setting('cuego.test.order')::uuid,current_setting('cuego.test.token')::uuid)->>'total_pence');
insert into pg_temp.cuego_checks select 'idempotency',(public.place_demo_order(current_setting('cuego.test.location')::uuid,current_setting('cuego.test.table')::uuid,current_setting('cuego.test.token')::uuid,current_setting('cuego.test.lines')::jsonb,'','')::text=current_setting('cuego.test.order'))::text;
insert into pg_temp.cuego_checks select 'wrong_order_token_denied',(public.get_demo_order(current_setting('cuego.test.order')::uuid,gen_random_uuid()) is null)::text;
do $check$ begin
 begin perform id from public.orders;raise exception 'Anonymous order access unexpectedly allowed';
 exception when insufficient_privilege then insert into pg_temp.cuego_checks values('anonymous_private_orders_denied','true');end;
end $check$;
do $t$ begin
 begin perform public.place_table_order('thevictoryinn',current_setting('cuego.test.table')::uuid,gen_random_uuid(),'[]'::jsonb,'');raise exception 'Legacy unexpectedly allowed';
 exception when raise_exception then if sqlerrm<>'Use the demo checkout for this location' then raise;end if;end;
 insert into pg_temp.cuego_checks values('legacy_checkout_blocked','true');
end $t$;
reset role;
select set_config('request.jwt.claim.sub',current_setting('cuego.test.owner'),true);
set local role authenticated;
insert into pg_temp.cuego_checks select 'routed_stations',count(*)::text from public.order_station_states where order_id=current_setting('cuego.test.order')::uuid;
update public.order_station_states set status='accepted' where order_id=current_setting('cuego.test.order')::uuid;
update public.order_station_states set status='preparing' where order_id=current_setting('cuego.test.order')::uuid;
update public.order_station_states set status='ready' where order_id=current_setting('cuego.test.order')::uuid;
update public.orders set status='delivered' where id=current_setting('cuego.test.order')::uuid;
insert into pg_temp.cuego_checks select 'customer_final_status',public.get_demo_order(current_setting('cuego.test.order')::uuid,current_setting('cuego.test.token')::uuid)->>'status';
with changed as(update public.menu_items set price_pence=price_pence+1 where venue_id=current_setting('cuego.test.location')::uuid and name='Coca-Cola' returning id) insert into pg_temp.cuego_checks select 'manager_can_edit_price',count(*)::text from changed;
reset role;
select set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
set local role authenticated;
insert into pg_temp.cuego_checks select 'unrelated_user_private_orders_visible',count(*)::text from public.orders;
with changed as(update public.menu_items set price_pence=1 where venue_id=current_setting('cuego.test.location')::uuid returning id) insert into pg_temp.cuego_checks select 'unrelated_user_products_changed',count(*)::text from changed;
do $assert$
begin
 if exists(
  select 1 from (values ('trusted_total','3140'),('idempotency','true'),
  ('wrong_order_token_denied','true'),('anonymous_private_orders_denied','true'),
  ('legacy_checkout_blocked','true'),('routed_stations','2'),('customer_final_status','delivered'),
  ('manager_can_edit_price','1'),('unrelated_user_private_orders_visible','0'),
  ('unrelated_user_products_changed','0')) expected(name,result)
  left join pg_temp.cuego_checks actual using(name)
  where actual.result is distinct from expected.result
 ) then raise exception 'Cuego order flow checks failed'; end if;
end $assert$;
select * from pg_temp.cuego_checks;
rollback;
