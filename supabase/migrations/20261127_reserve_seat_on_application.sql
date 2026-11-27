-- Holpin: reservar el asiento al postularse y liberarlo si el conductor rechaza.
-- Ejecutar una sola vez en Supabase > SQL Editor.

create or replace function public.holpin_sync_trip_request_seat()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.trips
      set seats_left = seats_left - 1,
          sold_out_at = case when seats_left - 1 = 0 then now() else null end
      where id = new.trip_id
        and seats_left > 0
        and completed_at is null;
    if not found then
      raise exception 'No quedan asientos disponibles para este viaje';
    end if;
    return new;
  end if;

  if old.status <> 'rejected' and new.status = 'rejected' then
    update public.trips
      set seats_left = least(seats_left + 1, seats),
          sold_out_at = null
      where id = new.trip_id;
  elsif old.status = 'rejected' and new.status <> 'rejected' then
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
end;
$$;

drop trigger if exists holpin_trip_request_seat on public.trip_requests;
drop trigger if exists holpin_trip_request_seat_insert on public.trip_requests;
drop trigger if exists holpin_trip_request_seat_update on public.trip_requests;

create trigger holpin_trip_request_seat_insert
after insert on public.trip_requests
for each row execute function public.holpin_sync_trip_request_seat();

create trigger holpin_trip_request_seat_update
after update of status on public.trip_requests
for each row execute function public.holpin_sync_trip_request_seat();
