-- SRG Warehouse Stock: database setup for Supabase.
-- Run this once in your Supabase project: Dashboard → SQL Editor → New query → paste → Run.
-- It is safe to run again: it only creates what is missing and replaces the functions and policies.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

-- One row per staff member, holding the name shown in the movement log.
create table if not exists public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  full_name  text not null default '' check (length(full_name) <= 80),
  created_at timestamptz not null default now()
);

-- One row per stock line.
create table if not exists public.items (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (length(name) between 1 and 140),
  sku        text not null default '' check (length(sku) <= 60),
  category   text not null default '' check (length(category) <= 60),
  location   text not null default '' check (length(location) <= 40),
  unit       text not null default 'each' check (length(unit) <= 20),
  qty        numeric not null default 0,
  min_qty    numeric not null default 0 check (min_qty >= 0),
  supplier   text not null default '' check (length(supplier) <= 100),
  notes      text not null default '' check (length(notes) <= 2000),
  photos     text[] not null default '{}',
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid() references auth.users (id) on delete set null
);

-- One row per stock movement (book in, book out, stocktake count).
-- item_id goes null if the item is deleted, so history is kept with the item's name.
create table if not exists public.moves (
  id         uuid primary key default gen_random_uuid(),
  item_id    uuid references public.items (id) on delete set null,
  item_name  text not null,
  sku        text not null default '',
  unit       text not null default '',
  location   text not null default '',
  type       text not null check (type in ('in', 'out', 'count')),
  qty        numeric not null,
  delta      numeric not null,
  balance    numeric not null,
  venue      text not null default '',
  reason     text not null default '',
  ref        text not null default '',
  note       text not null default '',
  by_user    uuid references auth.users (id) on delete set null,
  by_name    text not null default '',
  created_at timestamptz not null default now()
);

create index if not exists moves_created_at_idx on public.moves (created_at desc);
create index if not exists moves_item_idx on public.moves (item_id, created_at desc);
create index if not exists moves_venue_idx on public.moves (venue, created_at desc);

-- ---------------------------------------------------------------------------
-- Keep updated_at / updated_by current on every item edit
-- ---------------------------------------------------------------------------

create or replace function public.touch_item() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  new.updated_by := coalesce(auth.uid(), new.updated_by);
  return new;
end $$;

drop trigger if exists items_touch on public.items;
create trigger items_touch before update on public.items
  for each row execute function public.touch_item();

-- ---------------------------------------------------------------------------
-- New staff accounts get a profile row automatically
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Booking stock. The ONLY way quantities change: it locks the item row,
-- so two people booking the same item at once can't overwrite each other.
-- ---------------------------------------------------------------------------

create or replace function public.book_stock(
  p_item   uuid,
  p_type   text,
  p_qty    numeric,
  p_venue  text default '',
  p_reason text default '',
  p_ref    text default '',
  p_note   text default ''
) returns public.moves
language plpgsql security definer set search_path = public as $$
declare
  it      public.items;
  v_delta numeric;
  v_bal   numeric;
  v_name  text;
  m       public.moves;
begin
  if auth.uid() is null then
    raise exception 'You need to sign in first.' using errcode = '42501';
  end if;
  if p_type not in ('in', 'out', 'count') then
    raise exception 'Unknown movement type.';
  end if;
  if p_qty is null or p_qty < 0 or (p_type <> 'count' and p_qty = 0) then
    raise exception 'Enter a quantity above zero.';
  end if;
  if p_type = 'out' and coalesce(btrim(p_venue), '') = '' then
    raise exception 'Choose which venue the stock is going to.';
  end if;

  select * into it from public.items where id = p_item for update;
  if not found then
    raise exception 'This item has been deleted.';
  end if;

  v_delta := case p_type when 'in' then p_qty when 'out' then -p_qty else p_qty - it.qty end;
  v_bal   := it.qty + v_delta;

  if p_type = 'out' and v_bal < 0 then
    raise exception 'Only % % on hand. Do a stocktake count if that''s wrong.', trim_scale(it.qty), it.unit;
  end if;

  update public.items set qty = v_bal where id = p_item;

  select full_name into v_name from public.profiles where id = auth.uid();

  insert into public.moves (item_id, item_name, sku, unit, location, type, qty, delta, balance,
                            venue, reason, ref, note, by_user, by_name)
  values (p_item, it.name, it.sku, it.unit, it.location, p_type, p_qty, v_delta, v_bal,
          left(coalesce(p_venue, ''), 100), left(coalesce(p_reason, ''), 100),
          left(coalesce(p_ref, ''), 100), left(coalesce(p_note, ''), 500),
          auth.uid(), coalesce(v_name, ''))
  returning * into m;

  return m;
end $$;

revoke all on function public.book_stock(uuid, text, numeric, text, text, text, text) from public, anon;
grant execute on function public.book_stock(uuid, text, numeric, text, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Access rules: only signed-in staff can see or change anything.
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.items    enable row level security;
alter table public.moves    enable row level security;

drop policy if exists "staff read profiles"   on public.profiles;
drop policy if exists "staff add own profile" on public.profiles;
drop policy if exists "staff edit own profile" on public.profiles;
create policy "staff read profiles"    on public.profiles for select to authenticated using (true);
create policy "staff add own profile"  on public.profiles for insert to authenticated with check (id = auth.uid());
create policy "staff edit own profile" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "staff read items"   on public.items;
drop policy if exists "staff add items"    on public.items;
drop policy if exists "staff edit items"   on public.items;
drop policy if exists "staff delete items" on public.items;
create policy "staff read items"   on public.items for select to authenticated using (true);
create policy "staff add items"    on public.items for insert to authenticated with check (true);
create policy "staff edit items"   on public.items for update to authenticated using (true) with check (true);
create policy "staff delete items" on public.items for delete to authenticated using (true);

-- Movements are read-only to the app; they are written by book_stock() only, so the log can't be edited.
drop policy if exists "staff read moves" on public.moves;
create policy "staff read moves" on public.moves for select to authenticated using (true);

-- Quantity can't be typed in directly: staff can edit every item field except qty.
revoke all on public.items, public.moves, public.profiles from anon;
revoke insert, update on public.items from authenticated;
grant insert (name, sku, category, location, unit, min_qty, supplier, notes, photos) on public.items to authenticated;
grant update (name, sku, category, location, unit, min_qty, supplier, notes, photos) on public.items to authenticated;
revoke insert, update, delete on public.moves from authenticated;

-- ---------------------------------------------------------------------------
-- Photo storage: a private bucket only signed-in staff can read or write.
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('item-photos', 'item-photos', false, 10485760, array['image/jpeg', 'image/png', 'image/webp', 'image/gif'])
on conflict (id) do nothing;

drop policy if exists "staff view item photos"   on storage.objects;
drop policy if exists "staff upload item photos" on storage.objects;
drop policy if exists "staff delete item photos" on storage.objects;
create policy "staff view item photos"   on storage.objects for select to authenticated using (bucket_id = 'item-photos');
create policy "staff upload item photos" on storage.objects for insert to authenticated with check (bucket_id = 'item-photos');
create policy "staff delete item photos" on storage.objects for delete to authenticated using (bucket_id = 'item-photos');

-- ---------------------------------------------------------------------------
-- Live updates: phones refresh when anyone changes stock.
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'items') then
    alter publication supabase_realtime add table public.items;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'moves') then
    alter publication supabase_realtime add table public.moves;
  end if;
end $$;
