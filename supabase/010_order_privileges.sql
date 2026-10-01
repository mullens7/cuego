-- RLS controls rows; column grants also prevent staff from changing payment or price fields.
revoke all on public.orders,public.order_items from anon;
revoke insert,delete,truncate,references,trigger,update on public.orders,public.order_items from authenticated;
grant select on public.orders,public.order_items to authenticated;
grant update(status,delivered_at) on public.orders to authenticated;
-- Order snapshots are written only by trusted SECURITY DEFINER order RPCs.
-- New venues must be created by the organisation RPC, which creates matching organisation/location records atomically.
drop policy venues_create on public.venues;
revoke insert,delete,truncate,trigger on public.venues from anon,authenticated;
