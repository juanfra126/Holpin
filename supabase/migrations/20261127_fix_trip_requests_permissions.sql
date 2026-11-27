-- Holpin: conceder permisos SQL a la API de Supabase.
-- Las políticas RLS controlan QUÉ filas puede usar cada usuario;
-- estos GRANT habilitan el acceso a las tablas desde la API.

grant usage on schema public to authenticated;
grant select, insert, update on table public.trip_requests to authenticated;
grant select, insert on table public.trip_ratings to authenticated;

-- Lectura de valoraciones visible para todos los usuarios de la app.
grant select on table public.trip_ratings to anon;

-- Reafirmar RLS y políticas de acceso a postulaciones.
alter table public.trip_requests enable row level security;
alter table public.trip_ratings enable row level security;

drop policy if exists "Trip requests visible to involved users" on public.trip_requests;
create policy "Trip requests visible to involved users"
on public.trip_requests for select to authenticated
using (
  passenger_id = (select auth.uid())
  or exists (
    select 1 from public.trips t
    where t.id = trip_requests.trip_id
      and t.driver_id = (select auth.uid())
  )
);

drop policy if exists "Passengers can apply to trips" on public.trip_requests;
create policy "Passengers can apply to trips"
on public.trip_requests for insert to authenticated
with check (
  passenger_id = (select auth.uid())
  and status = 'pending'
  and exists (
    select 1 from public.trips t
    where t.id = trip_requests.trip_id
      and t.driver_id <> (select auth.uid())
      and t.seats_left > 0
      and t.completed_at is null
  )
);

drop policy if exists "Drivers can manage trip requests" on public.trip_requests;
create policy "Drivers can manage trip requests"
on public.trip_requests for update to authenticated
using (
  exists (
    select 1 from public.trips t
    where t.id = trip_requests.trip_id
      and t.driver_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1 from public.trips t
    where t.id = trip_requests.trip_id
      and t.driver_id = (select auth.uid())
  )
);
