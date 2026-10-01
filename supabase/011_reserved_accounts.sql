-- Access reservations are private server configuration, never user-editable metadata.
create schema cuego_private;
revoke all on schema cuego_private from public,anon,authenticated;
create table cuego_private.platform_admins(user_id uuid primary key references auth.users(id) on delete cascade,created_at timestamptz not null default now());
create table cuego_private.account_reservations(
 email text primary key check(email=lower(email)), access_kind text not null check(access_kind in ('platform_admin','venue_owner')),
 organisation_name text,organisation_slug text,location_name text,location_slug text,
 assigned_user_id uuid references auth.users(id) on delete set null
);
revoke all on all tables in schema cuego_private from public,anon,authenticated;
insert into cuego_private.account_reservations(email,access_kind,organisation_name,organisation_slug,location_name,location_slug) values
 ('freddie@mullens.com','platform_admin',null,null,null,null),
 ('freddiemullenuk@icloud.com','venue_owner','The Victory Inn','the-victory-inn','The Victory Inn — Hamble','hamble');
create function cuego_private.provision_reserved_account()
returns trigger language plpgsql security definer set search_path=''
as $$
declare r cuego_private.account_reservations%rowtype;v_org uuid;v_location uuid;
begin
 if new.email_confirmed_at is null then return new; end if;
 select * into r from cuego_private.account_reservations where email=lower(new.email) for update;
 if not found or (r.assigned_user_id is not null and r.assigned_user_id<>new.id) then return new;end if;
 if r.access_kind='platform_admin' then
  insert into cuego_private.platform_admins(user_id) values(new.id) on conflict do nothing;
 else
  insert into public.organisations(name,slug) values(r.organisation_name,r.organisation_slug) on conflict(slug) do nothing;
  select id into v_org from public.organisations where slug=r.organisation_slug;
  insert into public.organisation_members(organisation_id,user_id,role) values(v_org,new.id,'owner') on conflict do nothing;
  select id into v_location from public.locations where organisation_id=v_org and slug=r.location_slug;
  if v_location is null then
   insert into public.venues(owner_user_id,slug,name) values(new.id,r.organisation_slug||'-'||r.location_slug,r.location_name) returning id into v_location;
   insert into public.locations(id,organisation_id,slug,name,demo_mode) values(v_location,v_org,r.location_slug,r.location_name,true);
   insert into public.preparation_stations(location_id,name) values(v_location,'Bar'),(v_location,'Kitchen');
   insert into public.venue_tables(venue_id,label) values(v_location,'12');
  end if;
 end if;
 update cuego_private.account_reservations set assigned_user_id=new.id where email=r.email;
 return new;
end;
$$;
revoke all on function cuego_private.provision_reserved_account() from public,anon,authenticated;
create trigger cuego_reserved_account after insert or update of email,email_confirmed_at on auth.users for each row execute function cuego_private.provision_reserved_account();
create function public.cuego_access()
returns jsonb language sql stable security definer set search_path=''
as $$ select jsonb_build_object('platform_admin',exists(select 1 from cuego_private.platform_admins where user_id=(select auth.uid()))); $$;
revoke all on function public.cuego_access() from public,anon;
grant execute on function public.cuego_access() to authenticated;
create function public.cuego_platform_overview()
returns jsonb language plpgsql stable security definer set search_path=''
as $$
begin
 if not exists(select 1 from cuego_private.platform_admins where user_id=(select auth.uid())) then raise exception 'Platform access required' using errcode='42501';end if;
 return jsonb_build_object(
 'organisations',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'slug',slug)) from public.organisations),'[]'::jsonb),
 'locations',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'name',l.name,'slug',l.slug,'organisation_id',l.organisation_id,'demo_mode',l.demo_mode,'accepting_orders',v.accepting_orders)) from public.locations l join public.venues v on v.id=l.id),'[]'::jsonb),
 'domains',coalesce((select jsonb_agg(jsonb_build_object('hostname',hostname,'location_id',location_id,'verification_status',verification_status)) from public.location_domains),'[]'::jsonb),
 'members',coalesce((select jsonb_agg(jsonb_build_object('email',u.email,'role',m.role,'organisation_id',m.organisation_id)) from public.organisation_members m join auth.users u on u.id=m.user_id),'[]'::jsonb),
 'demo_orders',(select count(*) from public.orders where order_kind='demo'),
 'paid_orders',(select count(*) from public.orders where payment_status='paid' and order_kind<>'demo'));
end;
$$;
revoke all on function public.cuego_platform_overview() from public,anon;
grant execute on function public.cuego_platform_overview() to authenticated;
