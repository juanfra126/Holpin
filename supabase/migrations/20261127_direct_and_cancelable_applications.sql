-- Holpin: postulaciones directas y cancelables por el pasajero.
-- Ejecutar una vez en Supabase > SQL Editor.

grant usage on schema public to authenticated;
grant select, insert, update, delete on table public.trip_requests to authenticated;

drop policy if exists "Passengers can apply to trips" on public.trip_requests;
create policy "Passengers can apply to trips"
on public.trip_requests for insert to authenticated
with check (
  passenger_id = (select auth.uid())
  and status = 'accepted'
  and exists (
    select 1 from public.trips t
    where t.id = trip_requests.trip_id
      and t.driver_id <> (select auth.uid())
      and t.seats_left > 0
      and t.completed_at is null
  )
);

drop policy if exists "Passengers can cancel own applications" on public.trip_requests;
create policy "Passengers can cancel own applications"
on public.trip_requests for delete to authenticated
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
  elsif tg_op = 'DELETE' then
    update public.trips
      set seats_left = least(seats_left + 1, seats),
          sold_out_at = null
      where id = old.trip_id;
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists holpin_trip_request_seat_delete on public.trip_requests;
create trigger holpin_trip_request_seat_delete
after delete on public.trip_requests
for each row execute function public.holpin_sync_trip_request_seat();
