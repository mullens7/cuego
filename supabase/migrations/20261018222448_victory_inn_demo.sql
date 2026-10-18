-- A reusable classic theme; existing locations retain their current appearance.
alter table public.locations add column theme_style text not null default 'modern'
 check(theme_style in ('modern','classic'));
grant update(theme_style) on public.locations to authenticated;

create or replace function public.resolve_ordering_location(p_hostname text default null,p_organisation_slug text default null,p_location_slug text default null)
returns jsonb language sql stable security definer set search_path=''
as $$
 select jsonb_build_object('id',l.id,'organisation_id',o.id,'organisation_slug',o.slug,'location_slug',l.slug,
  'name',l.name,'logo_url',l.logo_url,'primary_colour',l.primary_colour,'accent_colour',l.accent_colour,
  'theme_style',l.theme_style,'demo_mode',l.demo_mode,'hostname',d.hostname)
 from public.locations l join public.organisations o on o.id=l.organisation_id
 join public.venues v on v.id=l.id
 left join public.location_domains d on d.location_id=l.id and d.hostname=lower(trim(trailing '.' from coalesce(p_hostname,''))) and d.verification_status='verified'
 where v.accepting_orders=true and (
  (p_hostname is not null and d.id is not null)
  or (p_hostname is null and o.slug=p_organisation_slug and (l.slug=p_location_slug or (p_location_slug is null and (select count(*) from public.locations s where s.organisation_id=o.id)=1)))
 ) order by l.created_at limit 1;
$$;
revoke all on function public.resolve_ordering_location(text,text,text) from public;
grant execute on function public.resolve_ordering_location(text,text,text) to anon,authenticated;

-- The verified Cuego administrator manages this demo until the reserved venue
-- account is confirmed. No fabricated Auth user, password or email confirmation.
do $seed$
declare v_owner uuid;v_org uuid;v_location uuid;v_bar uuid;v_kitchen uuid;
 v_cat uuid;v_item uuid;v_group uuid;r jsonb;g jsonb;opt jsonb;v_order integer:=0;
begin
 select a.user_id into v_owner from cuego_private.platform_admins a
 join auth.users u on u.id=a.user_id
 where lower(u.email)='freddie@mullens.com' and u.email_confirmed_at is not null;
 if v_owner is null then raise exception 'A verified Cuego platform administrator is required';end if;
 insert into public.organisations(slug,name) values('thevictoryinn','The Victory Inn') on conflict(slug) do nothing;
 select id into v_org from public.organisations where slug='thevictoryinn';
 insert into public.organisation_members(organisation_id,user_id,role) values(v_org,v_owner,'admin') on conflict do nothing;
 select id into v_location from public.locations where organisation_id=v_org and slug='hamble';
 if v_location is null then
  insert into public.venues(owner_user_id,slug,name,accepting_orders)
   values(v_owner,'thevictoryinn','The Victory Inn',true) returning id into v_location;
  insert into public.locations(id,organisation_id,slug,name,logo_url,primary_colour,accent_colour,theme_style,demo_mode)
   values(v_location,v_org,'hamble','The Victory Inn','/assets/venues/thevictoryinn/logo.webp','#191919','#ffda46','classic',true);
 end if;
 -- The existing verified-signup trigger attaches this reserved account to the
 -- seeded organisation/location rather than provisioning a second tenant.
 update cuego_private.account_reservations set organisation_slug='thevictoryinn'
  where email='freddiemullenuk@icloud.com' and assigned_user_id is null;
 insert into public.preparation_stations(location_id,name) values(v_location,'Bar'),(v_location,'Kitchen') on conflict(location_id,name) do nothing;
 select id into v_bar from public.preparation_stations where location_id=v_location and name='Bar';
 select id into v_kitchen from public.preparation_stations where location_id=v_location and name='Kitchen';
 insert into public.venue_tables(venue_id,label,area)
 select v_location,n::text,'Demo tables' from generate_series(1,12) n
 where not exists(select 1 from public.venue_tables t where t.venue_id=v_location and t.label=n::text);

 for r in select value from jsonb_array_elements($products$[
 {"category":"Draught & cider","station":"Bar","name":"Heineken","price":320,"description":"Choose a half or pint. Example demo pricing.","groups":[{"name":"Choose your size","min":1,"max":1,"options":[["Half pint",0],["Pint",300]]}]},
 {"category":"Draught & cider","station":"Bar","name":"Guinness","price":330,"description":"Choose a half or pint. Example demo pricing.","groups":[{"name":"Choose your size","min":1,"max":1,"options":[["Half pint",0],["Pint",320]]}]},
 {"category":"Draught & cider","station":"Bar","name":"Birra Moretti","price":330,"description":"Choose a half or pint. Example demo pricing.","groups":[{"name":"Choose your size","min":1,"max":1,"options":[["Half pint",0],["Pint",320]]}]},
 {"category":"Draught & cider","station":"Bar","name":"Aspall Cyder","price":300,"description":"Choose a half or pint. Example demo pricing.","groups":[{"name":"Choose your size","min":1,"max":1,"options":[["Half pint",0],["Pint",280]]}]},
 {"category":"Draught & cider","station":"Bar","name":"Cruzcampo","price":310,"description":"Choose a half or pint. Example demo pricing.","groups":[{"name":"Choose your size","min":1,"max":1,"options":[["Half pint",0],["Pint",290]]}]},
 {"category":"Soft drinks","station":"Bar","name":"Coca-Cola","price":320,"description":"Example drink and price for demonstration."},
 {"category":"Soft drinks","station":"Bar","name":"Diet Coke","price":300,"description":"Example drink and price for demonstration."},
 {"category":"Soft drinks","station":"Bar","name":"Sparkling water","price":250,"description":"Example drink and price for demonstration."},
 {"category":"Burgers","station":"Kitchen","name":"The Victory","price":1900,"description":"Beef, American cheese, bacon, salad and burger sauce. Brioche bun, fries and slaw.","groups":[{"name":"Leave something out","min":0,"max":3,"options":[["No tomato",0],["No lettuce",0],["No bacon",0]]}]},
 {"category":"Burgers","station":"Kitchen","name":"Fried Chicken Burger","price":1850,"description":"Buttermilk chicken with tomato, lettuce and mayo. Served with fries and slaw."},
 {"category":"Burgers","station":"Kitchen","name":"Halloumi & Avocado Burger","price":1700,"description":"Grilled halloumi, avocado, salad and sweet chilli. Served with fries and slaw."},
 {"category":"Loaded tots & fries","station":"Kitchen","name":"Beef Chilli Loaded Fries","price":1150,"description":"Beef chilli and melted cheddar.","groups":[{"name":"Choose your base","min":1,"max":1,"options":[["Fries",0],["Tater tots",0]]}]},
 {"category":"Loaded tots & fries","station":"Kitchen","name":"BBQ Loaded Fries","price":1150,"description":"Chicken, bacon, BBQ sauce and cheddar.","groups":[{"name":"Choose your base","min":1,"max":1,"options":[["Fries",0],["Tater tots",0]]}]},
 {"category":"Loaded tots & fries","station":"Kitchen","name":"Mixed Bean Chilli Loaded Fries","price":1050,"description":"Bean chilli with melted cheddar.","groups":[{"name":"Choose your base","min":1,"max":1,"options":[["Fries",0],["Tater tots",0]]}]},
 {"category":"Loaded tots & fries","station":"Kitchen","name":"BBQ Pulled Pork Loaded Fries","price":1150,"description":"Smoky BBQ pulled pork and cheddar.","groups":[{"name":"Choose your base","min":1,"max":1,"options":[["Fries",0],["Tater tots",0]]}]},
 {"category":"Salads","station":"Kitchen","name":"Caesar Salad","price":1400,"description":"Baby gem, Caesar dressing, croutons and Grana Padano.","groups":[{"name":"Add to your salad","min":0,"max":1,"options":[["Chicken & bacon",500]]}]},
 {"category":"Salads","station":"Kitchen","name":"Prawn & Avocado Salad","price":1900,"description":"Romaine, tomato, peppers and onion with lime, chilli and honey dressing."},
 {"category":"Sides","station":"Kitchen","name":"Chips","price":500},
 {"category":"Sides","station":"Kitchen","name":"Fries","price":500},
 {"category":"Sides","station":"Kitchen","name":"Garlic Ciabatta","price":550,"groups":[{"name":"Make it cheesy","min":0,"max":1,"options":[["Add cheese",100]]}]},
 {"category":"Sides","station":"Kitchen","name":"Onion Rings","price":550},
 {"category":"Sides","station":"Kitchen","name":"House Coleslaw","price":450},
 {"category":"Sides","station":"Kitchen","name":"Side Salad","price":550},
 {"category":"Sides","station":"Kitchen","name":"Mac & Cheese","price":700},
 {"category":"Sides","station":"Kitchen","name":"Cauliflower Bites","price":700}
]$products$::jsonb) loop
  select id into v_cat from public.menu_categories where venue_id=v_location and name=r->>'category';
  if v_cat is null then
   insert into public.menu_categories(venue_id,name,sort_order) values(v_location,r->>'category',v_order) returning id into v_cat;
  end if;
  select id into v_item from public.menu_items where venue_id=v_location and name=r->>'name';
  if v_item is null then
   insert into public.menu_items(venue_id,category_id,name,description,price_pence,station_id,sort_order,available,visibility)
   values(v_location,v_cat,r->>'name',coalesce(r->>'description',''),(r->>'price')::integer,
    case when r->>'station'='Bar' then v_bar else v_kitchen end,v_order,true,'available') returning id into v_item;
   for g in select value from jsonb_array_elements(coalesce(r->'groups','[]'::jsonb)) loop
    insert into public.modifier_groups(venue_id,item_id,name,min_choices,max_choices)
    values(v_location,v_item,g->>'name',(g->>'min')::integer,(g->>'max')::integer) returning id into v_group;
    for opt in select value from jsonb_array_elements(g->'options') loop
     insert into public.modifier_options(group_id,name,price_delta_pence,sort_order)
     values(v_group,opt->>0,(opt->>1)::integer,coalesce((select max(sort_order)+1 from public.modifier_options where group_id=v_group),0));
    end loop;
   end loop;
  end if;
  v_order=v_order+1;
 end loop;
end;
$seed$;

