-- Christmas Gif-Office · Supabase PostgreSQL schema
-- Ejecutar completo en Supabase SQL Editor con un usuario postgres.
create extension if not exists pgcrypto;

create table if not exists public.app_config (
  id integer primary key default 1 check (id = 1),
  admin_email text,
  created_at timestamptz not null default now()
);
insert into public.app_config (id, admin_email) values (1, null) on conflict (id) do nothing;
alter table public.app_config enable row level security;
-- No se crean políticas de lectura/escritura para clientes: solo funciones SECURITY DEFINER.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text unique not null,
  full_name text not null,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.event_settings (
  id integer primary key default 1 check (id = 1),
  event_title text not null default 'Christmas Gif-Office',
  target_participants integer not null default 15 check (target_participants > 1),
  voting_deadline timestamptz not null default (now() + interval '7 days'),
  wishlist_deadline timestamptz not null default (now() + interval '14 days'),
  force_voting_closed boolean not null default false,
  force_wishlist_closed boolean not null default false,
  winning_budget integer check (winning_budget in (200,300,500)),
  draw_completed boolean not null default false,
  draw_executed_at timestamptz
);
insert into public.event_settings (id) values (1) on conflict (id) do nothing;

create table if not exists public.budget_votes (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  amount integer not null check (amount in (200,300,500)),
  updated_at timestamptz not null default now()
);

create table if not exists public.wishlist_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 100),
  product_url text,
  image_url text,
  notes text check (notes is null or char_length(notes) <= 250),
  created_at timestamptz not null default now()
);
create index if not exists wishlist_items_user_id_idx on public.wishlist_items(user_id);

create table if not exists public.assignments (
  giver_id uuid primary key references public.profiles(id) on delete cascade,
  receiver_id uuid not null unique references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint assignments_no_self check (giver_id <> receiver_id)
);

-- Helper: privilegio administrativo consultado dentro de políticas RLS.
create or replace function public.is_current_user_admin()
returns boolean language sql stable security definer set search_path = public, pg_temp
as $$ select exists(select 1 from public.profiles where id = auth.uid() and is_admin = true); $$;
revoke all on function public.is_current_user_admin() from public;
grant execute on function public.is_current_user_admin() to authenticated;

-- Perfil automático; el primer usuario registrado es admin. Configura app_config.admin_email
-- antes de registrar usuarios si deseas que una cuenta concreta sea administradora.
create or replace function public.handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = public, auth, pg_temp
as $$
declare configured_admin text; first_user boolean;
begin
  -- Serializa altas simultáneas para que solo el primer perfil sea promovido por orden de registro.
  perform pg_advisory_xact_lock(72419031);
  select admin_email into configured_admin from public.app_config where id = 1;
  select not exists(select 1 from public.profiles) into first_user;
  insert into public.profiles(id,email,full_name,is_admin)
  values (
    new.id,
    lower(new.email),
    coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'),''), split_part(new.email,'@',1)),
    first_user or (configured_admin is not null and lower(new.email)=lower(configured_admin))
  )
  on conflict (id) do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_auth_user();

-- Límite de tres deseos, también protege escrituras fuera de la interfaz.
create or replace function public.enforce_wishlist_limit()
returns trigger language plpgsql security definer set search_path = public, pg_temp
as $$
declare item_count integer;
begin
  if tg_op = 'INSERT' then
    perform pg_advisory_xact_lock(hashtextextended(new.user_id::text, 0));
    select count(*) into item_count from public.wishlist_items where user_id = new.user_id;
    if item_count >= 3 then raise exception 'Solo puedes registrar un máximo de 3 deseos.' using errcode='23514'; end if;
  end if;
  return new;
end; $$;
drop trigger if exists wishlist_max_three on public.wishlist_items;
create trigger wishlist_max_three before insert on public.wishlist_items
for each row execute procedure public.enforce_wishlist_limit();

-- Estados de escritura centralizados en SQL (hora de servidor, no del navegador).
create or replace function public.voting_is_open()
returns boolean language sql stable security definer set search_path = public, pg_temp
as $$ select not draw_completed and not force_voting_closed and now() < voting_deadline from public.event_settings where id=1; $$;
create or replace function public.wishlist_is_open()
returns boolean language sql stable security definer set search_path = public, pg_temp
as $$ select not draw_completed and not force_wishlist_closed and (now() >= voting_deadline or force_voting_closed) and now() < wishlist_deadline from public.event_settings where id=1; $$;

alter table public.profiles enable row level security;
alter table public.event_settings enable row level security;
alter table public.budget_votes enable row level security;
alter table public.wishlist_items enable row level security;
alter table public.assignments enable row level security;

drop policy if exists "profiles visible to authenticated" on public.profiles;
create policy "profiles visible to authenticated" on public.profiles for select to authenticated using (true);
drop policy if exists "profiles admin update" on public.profiles;
create policy "profiles admin update" on public.profiles for update to authenticated using (public.is_current_user_admin()) with check (public.is_current_user_admin());
-- Un usuario no puede cambiar su is_admin: no existe policy de update para sí mismo.

drop policy if exists "settings visible to authenticated" on public.event_settings;
create policy "settings visible to authenticated" on public.event_settings for select to authenticated using (true);
drop policy if exists "settings admin update" on public.event_settings;
create policy "settings admin update" on public.event_settings for update to authenticated using (public.is_current_user_admin()) with check (public.is_current_user_admin());

drop policy if exists "votes visible to authenticated" on public.budget_votes;
create policy "votes visible to authenticated" on public.budget_votes for select to authenticated using (true);
drop policy if exists "vote insert while open" on public.budget_votes;
create policy "vote insert while open" on public.budget_votes for insert to authenticated with check (user_id=auth.uid() and public.voting_is_open());
drop policy if exists "vote update while open" on public.budget_votes;
create policy "vote update while open" on public.budget_votes for update to authenticated using (user_id=auth.uid() and public.voting_is_open()) with check (user_id=auth.uid() and public.voting_is_open());

drop policy if exists "wishlist visible to authenticated" on public.wishlist_items;
create policy "wishlist visible to authenticated" on public.wishlist_items for select to authenticated using (true);
drop policy if exists "wishlist insert own while open" on public.wishlist_items;
create policy "wishlist insert own while open" on public.wishlist_items for insert to authenticated with check (user_id=auth.uid() and public.wishlist_is_open());
drop policy if exists "wishlist update own while open" on public.wishlist_items;
create policy "wishlist update own while open" on public.wishlist_items for update to authenticated using (user_id=auth.uid() and public.wishlist_is_open()) with check (user_id=auth.uid() and public.wishlist_is_open());
drop policy if exists "wishlist delete own while open" on public.wishlist_items;
create policy "wishlist delete own while open" on public.wishlist_items for delete to authenticated using (user_id=auth.uid() and public.wishlist_is_open());

-- Nunca crear una política SELECT global para assignments. Cada usuario ve solo su fila.
drop policy if exists "giver sees own assignment" on public.assignments;
create policy "giver sees own assignment" on public.assignments for select to authenticated using (giver_id=auth.uid());
-- No hay políticas INSERT/UPDATE/DELETE para assignments: solo la RPC puede escribir.

-- La función crea un ciclo aleatorio Fisher-Yates; todo ocurre en una transacción.
create or replace function public.execute_secret_santa_draw()
returns jsonb language plpgsql security definer set search_path = public, auth, pg_temp
as $$
declare
  participants uuid[];
  participant_count integer;
  i integer;
  j integer;
  temp_id uuid;
  v_id uuid;
  r_id uuid;
  chosen_budget integer;
  vote_total integer;
begin
  if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and is_admin=true) then
    raise exception 'Solo un administrador puede ejecutar el sorteo.' using errcode='42501';
  end if;
  perform 1 from public.event_settings where id=1 for update;
  if not found then raise exception 'No existe la configuración del evento.'; end if;
  if (select draw_completed from public.event_settings where id=1) then
    raise exception 'El sorteo ya fue ejecutado.';
  end if;
  if not ((select force_wishlist_closed from public.event_settings where id=1) or now() >= (select wishlist_deadline from public.event_settings where id=1)) then
    raise exception 'No se puede sortear mientras las listas estén abiertas.';
  end if;
  select array_agg(id order by id) into participants from public.profiles;
  participant_count := coalesce(array_length(participants,1),0);
  if participant_count < 2 then raise exception 'Se requieren al menos dos participantes.'; end if;
  if exists(select 1 from public.assignments) then raise exception 'Ya existen asignaciones; revisa el estado antes de continuar.'; end if;
  -- Fisher-Yates in-place shuffle (uniforme).
  for i in reverse participant_count..2 loop
    j := floor(random()*i)::integer + 1;
    temp_id := participants[i];
    participants[i] := participants[j];
    participants[j] := temp_id;
  end loop;
  for i in 1..participant_count loop
    v_id := participants[i];
    r_id := participants[case when i=participant_count then 1 else i+1 end];
    if v_id = r_id then raise exception 'Error interno: asignación propia detectada.'; end if;
    insert into public.assignments(giver_id,receiver_id) values(v_id,r_id);
  end loop;
  -- Presupuesto automático si el administrador no lo fijó manualmente.
  select winning_budget into chosen_budget from public.event_settings where id=1;
  if chosen_budget is null then
    select amount into chosen_budget from public.budget_votes group by amount order by count(*) desc, amount desc limit 1;
    if chosen_budget is null then chosen_budget := 300; end if;
  end if;
  update public.event_settings set draw_completed=true, draw_executed_at=now(), winning_budget=chosen_budget where id=1;
  return jsonb_build_object('success',true,'participants',participant_count,'draw_executed_at',now(),'winning_budget',chosen_budget);
end; $$;
revoke all on function public.execute_secret_santa_draw() from public;
grant execute on function public.execute_secret_santa_draw() to authenticated;

-- Supabase Storage: crear bucket público wishlist-images desde Dashboard o ejecutar esto.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('wishlist-images','wishlist-images',true,3145728,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=true, file_size_limit=3145728, allowed_mime_types=array['image/jpeg','image/png','image/webp'];
drop policy if exists "public can view wishlist images" on storage.objects;
create policy "public can view wishlist images" on storage.objects for select using (bucket_id='wishlist-images');
drop policy if exists "users upload own wishlist images" on storage.objects;
create policy "users upload own wishlist images" on storage.objects for insert to authenticated with check (bucket_id='wishlist-images' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "users update own wishlist images" on storage.objects;
create policy "users update own wishlist images" on storage.objects for update to authenticated using (bucket_id='wishlist-images' and (storage.foldername(name))[1]=auth.uid()::text) with check (bucket_id='wishlist-images' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "users delete own wishlist images" on storage.objects;
create policy "users delete own wishlist images" on storage.objects for delete to authenticated using (bucket_id='wishlist-images' and (storage.foldername(name))[1]=auth.uid()::text);

-- Privilegios SQL explícitos; RLS sigue determinando qué filas puede tocar cada usuario.
grant usage on schema public to authenticated;
grant select on public.profiles, public.event_settings, public.budget_votes, public.wishlist_items, public.assignments to authenticated;
grant insert, update on public.budget_votes to authenticated;
grant insert, update, delete on public.wishlist_items to authenticated;
grant update on public.event_settings to authenticated;
grant update on public.profiles to authenticated;
-- No otorgar INSERT/UPDATE/DELETE sobre assignments ni acceso a app_config.

-- Realtime: habilitar tablas desde Database > Replication si no aparecen en la publicación supabase_realtime.
