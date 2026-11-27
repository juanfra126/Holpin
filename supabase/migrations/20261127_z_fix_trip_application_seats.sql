-- Holpin: unifica permisos y reserva/liberación de asientos.
-- Ejecutar DESPUÉS de todas las migraciones 20261127 anteriores.
-- El frontend crea las postulaciones con status='accepted' para reservar
-- el asiento inmediatamente; esta migración alinea RLS y triggers con ese flujo.

alter table public.trip_requests enable row level security;

grant usage on schema public to authenticated;
grant select, insert, update, delete on table public.trip_requests to authenticated;

drop policy if exists "Passengers can apply to trips" on public.trip_requests;
create policy "Passengers can apply to trips"
on public.trip_requests
for insert to authenticated
with check (
  passenger_id = (select auth.uid())
  and status = 'accepted'
  and exists (
    select 1
    from public.trips t
    where t.id = trip_requests.trip_id
      and t.driver_id <> (select auth.uid())
      and t.seats_left > 0
      and t.completed_at is null
  )
);

drop policy if exists "Passengers can cancel own applications" on public.trip_requests;
create policy "Passengers can cancel own applications"
on public.trip_requests
for delete to authenticated
using (
  passenger_id = (select auth.uid())
  and status in ('pending','accepted')
);

create or replace function public.holpin_sync_trip_request_seat()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.status = 'accepted' then
      update public.trips
        set seats_left = seats_left - 1,
            sold_out_at = case when seats_left - 1 = 0 then now() else null end
        where id = new.trip_id
          and seats_left > 0
          and completed_at is null;
      if not found then
        raise exception 'No quedan asientos disponibles para este viaje';
      end if;
    end if;
    return new;

  elsif tg_op = 'DELETE' then
    if old.status = 'accepted' then
      update public.trips
        set seats_left = least(seats_left + 1, seats),
            sold_out_at = null
        where id = old.trip_id
          and completed_at is null;
    end if;
    return old;

  elsif tg_op = 'UPDATE' then
    if old.status is distinct from new.status then
      if old.status = 'accepted' and new.status <> 'accepted' then
        update public.trips
          set seats_left = least(seats_left + 1, seats),
              sold_out_at = null
          where id = new.trip_id
            and completed_at is null;
      elsif old.status <> 'accepted' and new.status = 'accepted' then
        update public.trips
          set seats_left = seats_left - 1,
              sold_out_at = case when seats_left - 1 = 0 then now() else null end
          where id = new.trip_id
            and seats_left > 0
            and completed_at is null;
        if not found then
          raise exception 'No quedan asientos disponibles para este viaje';
        end if;
      end if;
    end if;
    return new;
  end if;

  return null;
end;
$$;

-- Elimina las variantes creadas por las migraciones anteriores para evitar
-- que un mismo cambio descuente o devuelva asientos más de una vez.
drop trigger if exists holpin_trip_request_seat on public.trip_requests;
drop trigger if exists holpin_trip_request_seat_delete on public.trip_requests;
drop trigger if exists holpin_trip_request_seat_insert on public.trip_requests;
drop trigger if exists holpin_trip_request_seat_update on public.trip_requests;

create trigger holpin_trip_request_seat_insert
after insert on public.trip_requests
for each row execute function public.holpin_sync_trip_request_seat();

create trigger holpin_trip_request_seat_delete
after delete on public.trip_requests
for each row execute function public.holpin_sync_trip_request_seat();

create trigger holpin_trip_request_seat_update
after update of status on public.trip_requests
for each row execute function public.holpin_sync_trip_request_seat();
