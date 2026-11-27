-- Holpin: pedidos de viaje publicados por pasajeros
-- Ejecutar una sola vez en Supabase > SQL Editor.

create table if not exists public.ride_requests (
  id uuid primary key default gen_random_uuid(),
  passenger_id uuid not null references auth.users(id) on delete cascade,
  origin text not null check (char_length(trim(origin)) between 2 and 100),
  destination text not null check (char_length(trim(destination)) between 2 and 100),
  travel_date date not null,
  departure_time time,
  passengers smallint not null default 1 check (passengers between 1 and 8),
  note text not null default '' check (char_length(note) <= 500),
  status text not null default 'open' check (status in ('open','closed')),
  created_at timestamptz not null default now()
);

create index if not exists ride_requests_date_status_idx
  on public.ride_requests(travel_date, status, created_at desc);
create index if not exists ride_requests_passenger_idx
  on public.ride_requests(passenger_id);

alter table public.ride_requests enable row level security;

drop policy if exists "Ride requests are publicly readable" on public.ride_requests;
create policy "Ride requests are publicly readable"
  on public.ride_requests for select
  using (true);

drop policy if exists "Passengers can publish their own ride requests" on public.ride_requests;
create policy "Passengers can publish their own ride requests"
  on public.ride_requests for insert to authenticated
  with check (passenger_id = auth.uid() and status = 'open');

drop policy if exists "Passengers can update their own ride requests" on public.ride_requests;
create policy "Passengers can update their own ride requests"
  on public.ride_requests for update to authenticated
  using (passenger_id = auth.uid())
  with check (passenger_id = auth.uid());

drop policy if exists "Passengers can delete their own ride requests" on public.ride_requests;
create policy "Passengers can delete their own ride requests"
  on public.ride_requests for delete to authenticated
  using (passenger_id = auth.uid());

grant select on public.ride_requests to anon, authenticated;
grant insert, update, delete on public.ride_requests to authenticated;
