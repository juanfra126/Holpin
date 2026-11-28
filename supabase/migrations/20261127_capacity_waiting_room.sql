-- Holpin: control de admisión para el límite de conexiones del plan Free.
-- Cada navegador/dispositivo conserva un UUID propio; las sesiones vencen tras 75 s sin heartbeat.
create table if not exists public.holpin_active_sessions (
  session_id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  last_seen timestamptz not null default now()
);
create index if not exists holpin_active_sessions_last_seen_idx on public.holpin_active_sessions(last_seen);
create index if not exists holpin_active_sessions_user_idx on public.holpin_active_sessions(user_id);
alter table public.holpin_active_sessions enable row level security;
revoke all on public.holpin_active_sessions from anon, authenticated;
grant usage on schema public to authenticated;

create or replace function public.holpin_capacity_admit(p_session_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_user uuid := auth.uid(); v_count integer; v_limit constant integer := 180;
begin
  if v_user is null then raise exception 'authentication_required'; end if;
  if p_session_id is null then raise exception 'session_id_required'; end if;
  perform pg_advisory_xact_lock(hashtext('holpin_capacity_gate')::bigint);
  delete from public.holpin_active_sessions where last_seen < now() - interval '75 seconds';

  update public.holpin_active_sessions
  set last_seen = now()
  where session_id = p_session_id and user_id = v_user;
  if found then
    select count(*)::integer into v_count from public.holpin_active_sessions;
    return jsonb_build_object('allowed', true, 'active_count', v_count, 'capacity', v_limit);
  end if;

  select count(*)::integer into v_count from public.holpin_active_sessions;
  if v_count >= v_limit then
    return jsonb_build_object('allowed', false, 'active_count', v_count, 'capacity', v_limit);
  end if;

  insert into public.holpin_active_sessions(session_id,user_id,last_seen)
  values(p_session_id,v_user,now())
  on conflict(session_id) do update set user_id=excluded.user_id,last_seen=excluded.last_seen;
  select count(*)::integer into v_count from public.holpin_active_sessions;
  return jsonb_build_object('allowed', true, 'active_count', v_count, 'capacity', v_limit);
end; $$;

create or replace function public.holpin_capacity_release(p_session_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if auth.uid() is not null and p_session_id is not null then
    delete from public.holpin_active_sessions
    where session_id=p_session_id and user_id=auth.uid();
  end if;
end; $$;

revoke all on function public.holpin_capacity_admit(uuid) from public, anon;
revoke all on function public.holpin_capacity_release(uuid) from public, anon;
grant execute on function public.holpin_capacity_admit(uuid) to authenticated;
grant execute on function public.holpin_capacity_release(uuid) to authenticated;
