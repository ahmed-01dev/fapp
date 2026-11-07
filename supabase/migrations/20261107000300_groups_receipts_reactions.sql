-- WASEL messaging expansion: groups, channels, receipts, reactions and pins.
-- Applied incrementally after the initial WASEL core schema.

alter table public.conversations drop constraint if exists conversations_kind_check;
alter table public.conversations add constraint conversations_kind_check
  check (kind in ('direct','group','channel'));
alter table public.conversations
  add column if not exists title text,
  add column if not exists description text,
  add column if not exists photo_path text,
  add column if not exists is_public boolean not null default false,
  add column if not exists username text,
  add column if not exists updated_at timestamptz not null default now();
create unique index if not exists conversations_username_lower_uq
  on public.conversations(lower(username)) where username is not null;

alter table public.conversation_members
  add column if not exists role text not null default 'member'
  check (role in ('owner','admin','member'));
update public.conversation_members m
set role = 'owner'
from public.conversations c
where c.id = m.conversation_id and c.created_by = m.user_id and m.role <> 'owner';

create or replace function private.is_conversation_admin(p_conversation_id uuid, p_user_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.conversation_members m
    where m.conversation_id = p_conversation_id
      and m.user_id = p_user_id
      and m.role in ('owner','admin')
  );
$$;
revoke all on function private.is_conversation_admin(uuid,uuid) from public, anon;
grant execute on function private.is_conversation_admin(uuid,uuid) to authenticated;

create or replace function private.can_add_direct_member(p_conversation_id uuid, p_user_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select auth.uid() is not null
    and exists (
      select 1 from public.conversations c
      where c.id = p_conversation_id
        and (
          (c.kind = 'direct' and c.created_by = auth.uid()
            and (p_user_id = auth.uid() or
              (select count(*) from public.conversation_members m where m.conversation_id = c.id) < 2))
          or
          (c.kind in ('group','channel') and private.is_conversation_admin(c.id, auth.uid()))
        )
    );
$$;
revoke all on function private.can_add_direct_member(uuid,uuid) from public, anon;
grant execute on function private.can_add_direct_member(uuid,uuid) to authenticated;

drop policy if exists "creator adds members to own new conversation" on public.conversation_members;
create policy "admins add members"
  on public.conversation_members for insert to authenticated
  with check (private.can_add_direct_member(conversation_id, user_id));

drop policy if exists "members update conversation metadata" on public.conversations;
create policy "members update conversation metadata"
  on public.conversations for update to authenticated
  using (private.is_conversation_admin(id, (select auth.uid())))
  with check (private.is_conversation_admin(id, (select auth.uid())));

create table if not exists public.message_receipts (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  delivered_at timestamptz,
  read_at timestamptz,
  primary key (message_id, user_id)
);
alter table public.message_receipts enable row level security;
revoke all on public.message_receipts from public, anon;
grant select, insert, update on public.message_receipts to authenticated;
drop policy if exists "conversation members read receipts" on public.message_receipts;
create policy "conversation members read receipts" on public.message_receipts
  for select to authenticated using (
    exists (select 1 from public.messages msg
      where msg.id = message_id and private.is_conversation_member(msg.conversation_id, (select auth.uid())))
  );
drop policy if exists "users create own receipts" on public.message_receipts;
create policy "users create own receipts" on public.message_receipts
  for insert to authenticated with check (
    user_id = (select auth.uid()) and
    exists (select 1 from public.messages msg
      where msg.id = message_id and private.is_conversation_member(msg.conversation_id, (select auth.uid()))
        and msg.sender_id <> (select auth.uid()))
  );
drop policy if exists "users update own receipts" on public.message_receipts;
create policy "users update own receipts" on public.message_receipts
  for update to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create table if not exists public.message_reactions (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  emoji text not null check (char_length(emoji) between 1 and 32),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id, emoji)
);
alter table public.message_reactions enable row level security;
revoke all on public.message_reactions from public, anon;
grant select, insert, delete on public.message_reactions to authenticated;
drop policy if exists "members read reactions" on public.message_reactions;
create policy "members read reactions" on public.message_reactions
  for select to authenticated using (
    exists (select 1 from public.messages msg
      where msg.id = message_id and private.is_conversation_member(msg.conversation_id, (select auth.uid())))
  );
drop policy if exists "members add own reactions" on public.message_reactions;
create policy "members add own reactions" on public.message_reactions
  for insert to authenticated with check (
    user_id = (select auth.uid()) and
    exists (select 1 from public.messages msg
      where msg.id = message_id and private.is_conversation_member(msg.conversation_id, (select auth.uid())))
  );
drop policy if exists "users remove own reactions" on public.message_reactions;
create policy "users remove own reactions" on public.message_reactions
  for delete to authenticated using (user_id = (select auth.uid()));

create table if not exists public.pinned_messages (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  message_id uuid not null references public.messages(id) on delete cascade,
  pinned_by uuid not null references auth.users(id) on delete cascade,
  pinned_at timestamptz not null default now(),
  primary key (conversation_id, message_id)
);
alter table public.pinned_messages enable row level security;
revoke all on public.pinned_messages from public, anon;
grant select, insert, delete on public.pinned_messages to authenticated;
drop policy if exists "members read pinned messages" on public.pinned_messages;
create policy "members read pinned messages" on public.pinned_messages
  for select to authenticated using (private.is_conversation_member(conversation_id, (select auth.uid())));
drop policy if exists "admins pin messages" on public.pinned_messages;
create policy "admins pin messages" on public.pinned_messages
  for insert to authenticated with check (
    pinned_by = (select auth.uid()) and private.is_conversation_admin(conversation_id, (select auth.uid()))
  );
drop policy if exists "admins unpin messages" on public.pinned_messages;
create policy "admins unpin messages" on public.pinned_messages
  for delete to authenticated using (private.is_conversation_admin(conversation_id, (select auth.uid())));

create table if not exists public.typing_presence (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null default (now() + interval '8 seconds'),
  primary key (conversation_id, user_id)
);
create index if not exists typing_presence_expiry_idx on public.typing_presence(expires_at);
alter table public.typing_presence enable row level security;
revoke all on public.typing_presence from public, anon;
grant select, insert, update, delete on public.typing_presence to authenticated;
drop policy if exists "members see typing presence" on public.typing_presence;
create policy "members see typing presence" on public.typing_presence
  for select to authenticated using (private.is_conversation_member(conversation_id, (select auth.uid())));
drop policy if exists "users manage own typing presence" on public.typing_presence;
create policy "users manage own typing presence" on public.typing_presence
  for all to authenticated using (user_id = (select auth.uid()) and private.is_conversation_member(conversation_id, (select auth.uid())))
  with check (user_id = (select auth.uid()) and private.is_conversation_member(conversation_id, (select auth.uid())));

create index if not exists call_sessions_callee_idx on public.call_sessions(callee_id, created_at desc);
create index if not exists call_sessions_conversation_idx on public.call_sessions(conversation_id, created_at desc);
create index if not exists call_signals_sender_idx on public.call_signals(sender_id);
create index if not exists conversations_created_by_idx on public.conversations(created_by);
create index if not exists messages_sender_idx on public.messages(sender_id);
create index if not exists user_reports_message_idx on public.user_reports(message_id);
create index if not exists user_reports_reported_user_idx on public.user_reports(reported_user_id);
create index if not exists user_reports_reporter_idx on public.user_reports(reporter_id);

do $$
begin
  alter publication supabase_realtime add table public.message_receipts;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.message_reactions;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.typing_presence;
exception when duplicate_object then null;
end $$;
