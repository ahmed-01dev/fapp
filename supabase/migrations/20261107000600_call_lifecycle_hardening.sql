-- WASEL call lifecycle hardening: caller cancellation, participant hangup and call type.
alter table public.call_sessions
  add column if not exists call_type text not null default 'audio'
  check (call_type in ('audio','video'));

create unique index if not exists call_sessions_active_caller_uq
  on public.call_sessions(caller_id)
  where status in ('ringing','accepted');
create unique index if not exists call_sessions_active_callee_uq
  on public.call_sessions(callee_id)
  where status in ('ringing','accepted');

create or replace function private.guard_call_session_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id <> old.id
    or new.conversation_id <> old.conversation_id
    or new.caller_id <> old.caller_id
    or new.callee_id <> old.callee_id
    or new.created_at <> old.created_at
    or new.call_type <> old.call_type then
    raise exception 'call identity fields are immutable';
  end if;

  if auth.uid() = old.callee_id then
    if not (
      (old.status = 'ringing' and new.status in ('accepted','rejected','missed'))
      or (old.status = 'accepted' and new.status = 'ended')
    ) then
      raise exception 'invalid callee call state transition';
    end if;
  elsif auth.uid() = old.caller_id then
    if not (
      (old.status = 'ringing' and new.status = 'ended')
      or (old.status = 'accepted' and new.status = 'ended')
    ) then
      raise exception 'invalid caller call state transition';
    end if;
  else
    raise exception 'call participant required';
  end if;

  if new.status = 'accepted' and new.answered_at is null then
    new.answered_at := now();
  end if;
  if new.status in ('rejected','missed','ended') and new.ended_at is null then
    new.ended_at := now();
  end if;
  return new;
end;
$$;
revoke all on function private.guard_call_session_update() from public, anon, authenticated;

drop policy if exists "callee updates call state" on public.call_sessions;
drop policy if exists "participants update call state" on public.call_sessions;
create policy "participants update call state"
on public.call_sessions for update to authenticated
using (
  (select auth.uid()) in (caller_id, callee_id)
  and private.is_conversation_member(conversation_id, (select auth.uid()))
)
with check (
  (select auth.uid()) in (caller_id, callee_id)
  and private.is_conversation_member(conversation_id, (select auth.uid()))
);
