-- Holpin: descripciones, postulaciones y calificaciones
-- Ejecutar una sola vez en Supabase > SQL Editor.

alter table public.trips
  add column if not exists description text not null default '',
  add column if not exists completed_at timestamptz;

create table if not exists public.trip_requests (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  passenger_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','rejected')),
  created_at timestamptz not null default now(),
  unique (trip_id, passenger_id)
);

create table if not exists public.trip_ratings (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  passenger_id uuid not null references auth.users(id) on delete cascade,
  driver_id uuid not null references auth.users(id) on delete cascade,
  rating integer not null check (rating between 1 and 5),
  created_at timestamptz not null default now(),
  unique (trip_id, passenger_id)
);

create index if not exists trip_requests_trip_id_idx on public.trip_requests(trip_id);
create index if not exists trip_ratings_driver_id_idx on public.trip_ratings(driver_id);

alter table public.trip_requests enable row level security;
alter table public.trip_ratings enable row level security;

drop policy if exists "Trip requests visible to involved users" on public.trip_requests;
create policy "Trip requests visible to involved users"
on public.trip_requests for select to authenticated
using (
  passenger_id = auth.uid()
  or exists (select 1 from public.trips t where t.id = trip_requests.trip_id and t.driver_id = auth.uid())
);

drop policy if exists "Passengers can apply to trips" on public.trip_requests;
create policy "Passengers can apply to trips"
on public.trip_requests for insert to authenticated
with check (
  passenger_id = auth.uid()
  and status = 'pending'
  and exists (
    select 1 from public.trips t
    where t.id = trip_requests.trip_id and t.driver_id <> auth.uid()
      and t.seats_left > 0 and t.completed_at is null
  )
);

drop policy if exists "Drivers can manage trip requests" on public.trip_requests;
create policy "Drivers can manage trip requests"
on public.trip_requests for update to authenticated
using (exists (select 1 from public.trips t where t.id = trip_requests.trip_id and t.driver_id = auth.uid()))
with check (exists (select 1 from public.trips t where t.id = trip_id and t.driver_id = auth.uid()));

drop policy if exists "Ratings are publicly readable" on public.trip_ratings;
create policy "Ratings are publicly readable"
on public.trip_ratings for select
using (true);

drop policy if exists "Accepted passengers can rate completed trips" on public.trip_ratings;
create policy "Accepted passengers can rate completed trips"
on public.trip_ratings for insert to authenticated
with check (
  passenger_id = auth.uid()
  and exists (
    select 1 from public.trips t
    join public.trip_requests r on r.trip_id = t.id
    where t.id = trip_ratings.trip_id
      and t.driver_id = trip_ratings.driver_id
      and t.completed_at is not null
      and r.passenger_id = trip_ratings.passenger_id
      and r.status = 'accepted'
  )
);

-- Reserva el asiento de forma atómica al aceptar una postulación.
create or replace function public.holpin_sync_trip_request_seat()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'accepted' and old.status is distinct from 'accepted' then
    update public.trips
      set seats_left = seats_left - 1
      where id = new.trip_id and seats_left > 0 and completed_at is null;
    if not found then
      raise exception 'No quedan asientos disponibles para este viaje';
    end if;
  elsif old.status = 'accepted' and new.status <> 'accepted' then
    update public.trips set seats_left = seats_left + 1 where id = new.trip_id;
  end if;
  return new;
end;
$$;

drop trigger if exists holpin_trip_request_seat on public.trip_requests;
create trigger holpin_trip_request_seat
before update of status on public.trip_requests
for each row execute function public.holpin_sync_trip_request_seat();
