-- WASEL online/last-seen presence, visible only to contacts and shared conversation members.
create table if not exists public.user_presence (
  user_id uuid primary key references auth.users(id) on delete cascade,
  last_seen_at timestamptz not null default now(),
  online_until timestamptz,
  updated_at timestamptz not null default now()
);
create index if not exists user_presence_online_until_idx
  on public.user_presence(online_until) where online_until is not null;

alter table public.user_presence enable row level security;
revoke all on public.user_presence from public, anon;
grant select, insert, update, delete on public.user_presence to authenticated;

drop policy if exists "users see permitted presence" on public.user_presence;
create policy "users see permitted presence" on public.user_presence
  for select to authenticated using (
    user_id = (select auth.uid())
    or (
      (
        exists (
          select 1 from public.conversation_members mine
          join public.conversation_members theirs
            on theirs.conversation_id = mine.conversation_id
          where mine.user_id = (select auth.uid())
            and theirs.user_id = user_presence.user_id
        )
        or exists (
          select 1 from public.contact_requests r
          where r.status = 'accepted'
            and ((r.sender_id = (select auth.uid()) and r.recipient_id = user_presence.user_id)
              or (r.recipient_id = (select auth.uid()) and r.sender_id = user_presence.user_id))
        )
      )
      and not exists (
        select 1 from public.user_blocks b
        where (b.blocker_id = (select auth.uid()) and b.blocked_id = user_presence.user_id)
           or (b.blocker_id = user_presence.user_id and b.blocked_id = (select auth.uid()))
      )
    )
  );

drop policy if exists "users manage own presence" on public.user_presence;
create policy "users insert own presence" on public.user_presence
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "users update own presence" on public.user_presence
  for update to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "users delete own presence" on public.user_presence
  for delete to authenticated using (user_id = (select auth.uid()));

create or replace function private.clamp_presence_expiry()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.user_id <> auth.uid() then raise exception 'presence_owner_mismatch'; end if;
  if new.online_until is not null and new.online_until > now() + interval '2 minutes' then
    new.online_until := now() + interval '2 minutes';
  end if;
  if new.online_until is null then new.last_seen_at := now(); end if;
  new.updated_at := now();
  return new;
end;
$$;
revoke all on function private.clamp_presence_expiry() from public, anon, authenticated;
drop trigger if exists user_presence_clamp_expiry on public.user_presence;
create trigger user_presence_clamp_expiry
before insert or update on public.user_presence
for each row execute function private.clamp_presence_expiry();

create or replace function public.set_my_presence(p_online boolean)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  insert into public.user_presence(user_id, last_seen_at, online_until, updated_at)
  values (
    auth.uid(),
    now(),
    case when p_online then now() + interval '90 seconds' else null end,
    now()
  )
  on conflict (user_id) do update set
    online_until = case when p_online then now() + interval '90 seconds' else null end,
    last_seen_at = case when p_online then public.user_presence.last_seen_at else now() end,
    updated_at = now();
end;
$$;
revoke all on function public.set_my_presence(boolean) from public, anon;
grant execute on function public.set_my_presence(boolean) to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.user_presence;
exception when duplicate_object then null;
end $$;
