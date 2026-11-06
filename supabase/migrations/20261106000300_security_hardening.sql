-- WASEL security hardening: immutable identities, membership-safe edits, and block enforcement.
-- Apply only after 20261106000100_wasel_core.sql and 20261106000200_backend_foundation.sql.

-- A sender may edit/delete their own message only while remaining a member of its conversation.
drop policy if exists "sender edits own messages" on public.messages;
create policy "sender edits own messages"
  on public.messages for update to authenticated
  using (
    sender_id = (select auth.uid())
    and private.is_conversation_member(conversation_id, (select auth.uid()))
  )
  with check (
    sender_id = (select auth.uid())
    and private.is_conversation_member(conversation_id, (select auth.uid()))
  );

create or replace function private.guard_message_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
     or new.conversation_id is distinct from old.conversation_id
     or new.sender_id is distinct from old.sender_id
     or new.created_at is distinct from old.created_at then
    raise exception 'message identity fields are immutable';
  end if;

  if new.body is null or char_length(btrim(new.body)) < 1
     or char_length(new.body) > 10000 then
    raise exception 'invalid message body';
  end if;

  new.edited_at := case when new.body is distinct from old.body then now() else old.edited_at end;
  return new;
end;
$$;
revoke all on function private.guard_message_update() from public, anon, authenticated;
drop trigger if exists messages_guard_update on public.messages;
create trigger messages_guard_update
before update on public.messages
for each row execute function private.guard_message_update();

-- Prevent a recipient from rewriting request participants or manufacturing a conversation
-- by changing sender_id while accepting a request.
create or replace function private.guard_contact_request_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
     or new.sender_id is distinct from old.sender_id
     or new.recipient_id is distinct from old.recipient_id
     or new.created_at is distinct from old.created_at then
    raise exception 'contact request identity fields are immutable';
  end if;

  if old.status <> 'pending' or new.status not in ('accepted', 'rejected') then
    raise exception 'invalid contact request transition';
  end if;

  if new.status = 'accepted' and exists (
    select 1 from public.user_blocks b
    where (b.blocker_id = new.sender_id and b.blocked_id = new.recipient_id)
       or (b.blocker_id = new.recipient_id and b.blocked_id = new.sender_id)
  ) then
    raise exception 'contact request cannot be accepted because a participant is blocked';
  end if;

  new.updated_at := now();
  return new;
end;
$$;
revoke all on function private.guard_contact_request_update() from public, anon, authenticated;
drop trigger if exists contact_requests_guard_update on public.contact_requests;
create trigger contact_requests_guard_update
before update on public.contact_requests
for each row execute function private.guard_contact_request_update();

-- Block relationships apply in both directions to contact requests.
create or replace function private.reject_contact_request_when_blocked()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.user_blocks b
    where (b.blocker_id = new.sender_id and b.blocked_id = new.recipient_id)
       or (b.blocker_id = new.recipient_id and b.blocked_id = new.sender_id)
  ) then
    raise exception 'contact request is not allowed';
  end if;
  return new;
end;
$$;
revoke all on function private.reject_contact_request_when_blocked() from public, anon, authenticated;
drop trigger if exists contact_requests_block_guard on public.contact_requests;
create trigger contact_requests_block_guard
before insert on public.contact_requests
for each row execute function private.reject_contact_request_when_blocked();

-- Nearby discovery must respect blocks in either direction.
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
    and auth.uid() is not null
    and not exists (
      select 1 from public.user_blocks b
      where (b.blocker_id = me.user_id and b.blocked_id = other.user_id)
         or (b.blocker_id = other.user_id and b.blocked_id = me.user_id)
    );
$$;
revoke all on function public.nearby_matches() from public, anon;
grant execute on function public.nearby_matches() to authenticated;

-- Existing pending requests between the two users are no longer actionable.
update public.contact_requests r
set status = 'rejected', updated_at = now()
where r.status = 'pending'
  and exists (
    select 1 from public.user_blocks b
    where (b.blocker_id = r.sender_id and b.blocked_id = r.recipient_id)
       or (b.blocker_id = r.recipient_id and b.blocked_id = r.sender_id)
  );
