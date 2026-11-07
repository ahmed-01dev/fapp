-- WASEL private media storage and WebRTC signaling foundation.
-- Apply only to the dedicated WASEL Supabase project.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'chat-media',
  'chat-media',
  false,
  52428800,
  array[
    'image/jpeg','image/png','image/webp','image/gif',
    'video/mp4','video/webm',
    'audio/aac','audio/mpeg','audio/ogg','audio/mp4',
    'application/pdf'
  ]
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Object path convention: <conversation-uuid>/<uploader-uuid>/<random-file-name>
drop policy if exists "chat media members read" on storage.objects;
create policy "chat media members read"
on storage.objects for select to authenticated
using (
  bucket_id = 'chat-media'
  and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
  and private.is_conversation_member(
    ((storage.foldername(name))[1])::uuid,
    (select auth.uid())
  )
);

drop policy if exists "chat media members upload own folder" on storage.objects;
create policy "chat media members upload own folder"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'chat-media'
  and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
  and (storage.foldername(name))[2] = (select auth.uid())::text
  and private.is_conversation_member(
    ((storage.foldername(name))[1])::uuid,
    (select auth.uid())
  )
);

drop policy if exists "chat media owners update own files" on storage.objects;
create policy "chat media owners update own files"
on storage.objects for update to authenticated
using (
  bucket_id = 'chat-media'
  and (storage.foldername(name))[2] = (select auth.uid())::text
)
with check (
  bucket_id = 'chat-media'
  and (storage.foldername(name))[2] = (select auth.uid())::text
);

drop policy if exists "chat media owners delete own files" on storage.objects;
create policy "chat media owners delete own files"
on storage.objects for delete to authenticated
using (
  bucket_id = 'chat-media'
  and (storage.foldername(name))[2] = (select auth.uid())::text
);

create table if not exists public.call_sessions (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  caller_id uuid not null references auth.users(id) on delete cascade,
  callee_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'ringing'
    check (status in ('ringing','accepted','rejected','ended','missed')),
  created_at timestamptz not null default now(),
  answered_at timestamptz,
  ended_at timestamptz,
  check (caller_id <> callee_id)
);
create index if not exists call_sessions_participant_created_idx
  on public.call_sessions(caller_id, callee_id, created_at desc);

create table if not exists public.call_signals (
  id bigint generated always as identity primary key,
  call_id uuid not null references public.call_sessions(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  signal_type text not null check (signal_type in ('offer','answer','ice','hangup')),
  payload jsonb not null default '{}'::jsonb
    check (octet_length(payload::text) <= 12000),
  created_at timestamptz not null default now()
);
create index if not exists call_signals_call_created_idx
  on public.call_signals(call_id, created_at);

alter table public.call_sessions enable row level security;
alter table public.call_signals enable row level security;
revoke all on public.call_sessions, public.call_signals from anon, public;
grant select, insert, update on public.call_sessions to authenticated;
grant select, insert on public.call_signals to authenticated;

drop policy if exists "call participants read sessions" on public.call_sessions;
create policy "call participants read sessions"
on public.call_sessions for select to authenticated
using (
  (select auth.uid()) in (caller_id, callee_id)
  and private.is_conversation_member(conversation_id, (select auth.uid()))
);

drop policy if exists "conversation member starts direct call" on public.call_sessions;
create policy "conversation member starts direct call"
on public.call_sessions for insert to authenticated
with check (
  caller_id = (select auth.uid())
  and private.is_conversation_member(conversation_id, (select auth.uid()))
  and private.is_conversation_member(conversation_id, callee_id)
);

create or replace function private.guard_call_session_update()
returns trigger
language plpgsql
set search_path = ''
as $
begin
  if new.id <> old.id
    or new.conversation_id <> old.conversation_id
    or new.caller_id <> old.caller_id
    or new.callee_id <> old.callee_id
    or new.created_at <> old.created_at then
    raise exception 'call identity fields are immutable';
  end if;
  if auth.uid() <> old.callee_id then
    raise exception 'only the callee may change call state';
  end if;
  if not (
    (old.status = 'ringing' and new.status in ('accepted','rejected','missed'))
    or (old.status = 'accepted' and new.status = 'ended')
  ) then
    raise exception 'invalid call state transition';
  end if;
  if new.status = 'accepted' and new.answered_at is null then
    new.answered_at := now();
  end if;
  if new.status in ('rejected','missed','ended') and new.ended_at is null then
    new.ended_at := now();
  end if;
  return new;
end;
$;
revoke all on function private.guard_call_session_update() from public, anon, authenticated;
drop trigger if exists call_sessions_guard_update on public.call_sessions;
create trigger call_sessions_guard_update
before update on public.call_sessions
for each row execute function private.guard_call_session_update();

drop policy if exists "callee updates call state" on public.call_sessions;
create policy "callee updates call state"
on public.call_sessions for update to authenticated
using (callee_id = (select auth.uid()))
with check (callee_id = (select auth.uid()));

drop policy if exists "call participants read signals" on public.call_signals;
create policy "call participants read signals"
on public.call_signals for select to authenticated
using (
  exists (
    select 1 from public.call_sessions c
    where c.id = call_id
      and (select auth.uid()) in (c.caller_id, c.callee_id)
  )
);

drop policy if exists "call participants send own signals" on public.call_signals;
create policy "call participants send own signals"
on public.call_signals for insert to authenticated
with check (
  sender_id = (select auth.uid())
  and exists (
    select 1 from public.call_sessions c
    where c.id = call_id
      and (select auth.uid()) in (c.caller_id, c.callee_id)
      and c.status in ('ringing','accepted')
  )
);

do $$
begin
  alter publication supabase_realtime add table public.call_sessions;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.call_signals;
exception when duplicate_object then null;
end $$;
