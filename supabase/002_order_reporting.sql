alter table public.venues add column timezone text not null default 'Europe/London';

create or replace function public.venue_order_stats(p_venue_id uuid)
returns jsonb language sql stable security invoker set search_path = ''
as $$
  select jsonb_build_object(
    'today_count', count(*) filter (where (o.created_at at time zone v.timezone)::date = (now() at time zone v.timezone)::date and o.status <> 'cancelled'),
    'today_pence', coalesce(sum(o.total_pence) filter (where (o.created_at at time zone v.timezone)::date = (now() at time zone v.timezone)::date and o.status <> 'cancelled'),0),
    'week_count', count(*) filter (where (o.created_at at time zone v.timezone)::date >= (now() at time zone v.timezone)::date - 6 and o.status <> 'cancelled'),
    'week_pence', coalesce(sum(o.total_pence) filter (where (o.created_at at time zone v.timezone)::date >= (now() at time zone v.timezone)::date - 6 and o.status <> 'cancelled'),0)
  )
  from public.venues v left join public.orders o on o.venue_id=v.id
  where v.id=p_venue_id and v.owner_user_id=(select auth.uid())
  group by v.id;
$$;
revoke all on function public.venue_order_stats(uuid) from public;
grant execute on function public.venue_order_stats(uuid) to authenticated;

create or replace function public.enforce_order_status()
returns trigger language plpgsql set search_path = ''
as $$
declare v_line record;
begin
  if new.status <> old.status then
    if not ((old.status='new' and new.status in ('preparing','cancelled'))
       or (old.status='preparing' and new.status in ('ready','cancelled'))
       or (old.status='ready' and new.status='delivered')) then
      raise exception 'Invalid order status change';
    end if;
    if new.status='cancelled' then
      for v_line in select item_id,quantity from public.order_items where order_id=old.id and item_id is not null loop
        update public.menu_items set stock_count=stock_count+v_line.quantity
        where id=v_line.item_id and stock_count is not null;
      end loop;
    end if;
    new.delivered_at = case when new.status='delivered' then now() else null end;
  end if;
  return new;
end;
$$;
create trigger enforce_order_status_before_update before update on public.orders
for each row execute function public.enforce_order_status();
