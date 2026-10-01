-- Supabase's default function grants include anon directly in this project; explicitly remove it.
revoke execute on function public.create_cuego_organisation(text,text,text,text) from anon;
revoke execute on function public.is_location_member(uuid) from anon;
