-- WASEL MVP schema reference.
-- Review in a staging project first. PostGIS is used only for ephemeral Nearby matching.
create extension if not exists pgcrypto;
create extension if not exists postgis with schema extensions;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'New user' check (char_length(display_name) between 1 and 40),
  username text,
  phone_visibility text not null default 'contacts'
    check (phone_visibility in ('everyone','contacts','nobody')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint username_format check (
    username is null or username ~ '^[a-zA-Z0-9_.]{3,24}$'
  )
);
create unique index if not exists profiles_username_lower_uq
  on public.profiles (lower(username)) where username is not null;

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  kind text not null default 'direct' check (kind in ('direct')),
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);
create index if not exists conversation_members_user_idx
  on public.conversation_members(user_id, conversation_id);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 10000),
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  deleted_at timestamptz
);
create index if not exists messages_conversation_created_idx
  on public.messages(conversation_id, created_at desc);

-- Nearby coordinates are never selected directly by a client.
create table if not exists public.nearby_presence (
  user_id uuid primary key references auth.users(id) on delete cascade,
  location extensions.geography(point, 4326) not null,
  expires_at timestamptz not null,
  updated_at timestamptz not null default now()
);
create index if not exists nearby_presence_location_gix
  on public.nearby_presence using gist(location);
create index if not exists nearby_presence_expiry_idx
  on public.nearby_presence(expires_at);

alter table public.profiles enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
alter table public.nearby_presence enable row level security;

-- Profiles expose only non-sensitive fields through this table. Phone numbers remain in auth.users.
grant select, insert, update on public.profiles to authenticated;
grant select, insert on public.conversations to authenticated;
grant select, insert, delete on public.conversation_members to authenticated;
grant select, insert, update on public.messages to authenticated;
-- Nearby table is deliberately not granted to the client; RPCs below are the only access path.

drop policy if exists "profiles public safe read" on public.profiles;
create policy "profiles public safe read" on public.profiles
  for select to authenticated using (true);
drop policy if exists "profile owner insert" on public.profiles;
create policy "profile owner insert" on public.profiles
  for insert to authenticated with check ((select auth.uid()) = id);
drop policy if exists "profile owner update" on public.profiles;
create policy "profile owner update" on public.profiles
  for update to authenticated using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

drop policy if exists "conversation members can read conversation" on public.conversations;
create policy "conversation members can read conversation" on public.conversations
  for select to authenticated using (
    exists (select 1 from public.conversation_members m
      where m.conversation_id = id and m.user_id = (select auth.uid()))
  );
drop policy if exists "signed in user creates conversation" on public.conversations;
create policy "signed in user creates conversation" on public.conversations
  for insert to authenticated with check (created_by = (select auth.uid()));

drop policy if exists "members can read membership" on public.conversation_members;
create policy "members can read membership" on public.conversation_members
  for select to authenticated using (
    exists (select 1 from public.conversation_members mine
      where mine.conversation_id = conversation_id and mine.user_id = (select auth.uid()))
  );
drop policy if exists "creator adds members to own new conversation" on public.conversation_members;
create policy "creator adds members to own new conversation" on public.conversation_members
  for insert to authenticated with check (
    exists (select 1 from public.conversations c
      where c.id = conversation_id and c.created_by = (select auth.uid()))
    and (
      user_id = (select auth.uid())
      or (select count(*) from public.conversation_members m
          where m.conversation_id = conversation_id) < 2
    )
  );
drop policy if exists "members may leave conversation" on public.conversation_members;
create policy "members may leave conversation" on public.conversation_members
  for delete to authenticated using (user_id = (select auth.uid()));

drop policy if exists "members read messages" on public.messages;
create policy "members read messages" on public.messages
  for select to authenticated using (
    exists (select 1 from public.conversation_members m
      where m.conversation_id = conversation_id and m.user_id = (select auth.uid()))
  );
drop policy if exists "members send as themselves" on public.messages;
create policy "members send as themselves" on public.messages
  for insert to authenticated with check (
    sender_id = (select auth.uid())
    and exists (select 1 from public.conversation_members m
      where m.conversation_id = conversation_id and m.user_id = (select auth.uid()))
  );
drop policy if exists "sender edits own messages" on public.messages;
create policy "sender edits own messages" on public.messages
  for update to authenticated using (sender_id = (select auth.uid()))
  with check (sender_id = (select auth.uid()));

-- Public profile search returns no phone number or coordinates.
create or replace function public.search_profiles_by_username(p_query text)
returns table (id uuid, username text, display_name text)
language sql
stable
security invoker
set search_path = ''
as $$
  select p.id, p.username, p.display_name
  from public.profiles p
  where auth.uid() is not null
    and p.username is not null
    and lower(p.username) = lower(trim(leading '@' from p_query))
  limit 1;
$$;
revoke all on function public.search_profiles_by_username(text) from public, anon;
grant execute on function public.search_profiles_by_username(text) to authenticated;

-- Explicit opt-in is represented by the existence of a short-lived presence row.
-- Clients receive only a coarse distance bucket; never expose the geography column.
create or replace function public.nearby_enable(p_lat double precision, p_lon double precision)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if p_lat not between -90 and 90 or p_lon not between -180 and 180 then
    raise exception 'invalid coordinates';
  end if;
  insert into public.nearby_presence(user_id, location, expires_at, updated_at)
  values (
    auth.uid(),
    extensions.st_setsrid(extensions.st_makepoint(p_lon, p_lat), 4326)::extensions.geography,
    now() + interval '30 minutes',
    now()
  )
  on conflict (user_id) do update set
    location = excluded.location,
    expires_at = excluded.expires_at,
    updated_at = now();
end;
$$;

create or replace function public.nearby_disable()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.nearby_presence where user_id = auth.uid();
$$;

create or replace function public.nearby_matches()
returns table (user_id uuid, username text, display_name text, distance_band text)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.username, p.display_name,
    case
      when extensions.st_distance(me.location, other.location) <= 500 then 'within_500m'
      when extensions.st_distance(me.location, other.location) <= 1000 then 'within_1km'
      when extensions.st_distance(me.location, other.location) <= 3000 then 'within_3km'
      else 'within_5km'
    end as distance_band
  from public.nearby_presence me
  join public.nearby_presence other on other.user_id <> me.user_id
  join public.profiles p on p.id = other.user_id
  where me.user_id = auth.uid()
    and me.expires_at > now()
    and other.expires_at > now()
    and extensions.st_dwithin(me.location, other.location, 5000)
    and auth.uid() is not null;
$$;

revoke all on function public.nearby_enable(double precision,double precision) from public, anon;
revoke all on function public.nearby_disable() from public, anon;
revoke all on function public.nearby_matches() from public, anon;
grant execute on function public.nearby_enable(double precision,double precision) to authenticated;
grant execute on function public.nearby_disable() to authenticated;
grant execute on function public.nearby_matches() to authenticated;

-- Remove expired ephemeral locations. Schedule this statement with pg_cron or an external scheduler.
-- delete from public.nearby_presence where expires_at <= now();

-- Realtime publication for text messages. Run only if the table is not already present.
do $$
begin
  alter publication supabase_realtime add table public.messages;
exception when duplicate_object then null;
end $$;
