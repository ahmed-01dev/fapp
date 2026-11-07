-- WASEL privacy and identity hardening for direct conversations, pins, receipts and ownership.
create or replace function private.can_add_direct_member(p_conversation_id uuid, p_user_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select auth.uid() is not null
    and exists (
      select 1 from public.conversations c
      where c.id = p_conversation_id
        and (
          (
            c.kind = 'direct'
            and c.created_by = auth.uid()
            and (
              p_user_id = auth.uid()
              or (
                (select count(*) from public.conversation_members m where m.conversation_id = c.id) < 2
                and exists (
                  select 1 from public.contact_requests r
                  where r.status = 'accepted'
                    and ((r.sender_id = auth.uid() and r.recipient_id = p_user_id)
                      or (r.recipient_id = auth.uid() and r.sender_id = p_user_id))
                )
                and not private.are_users_blocked(auth.uid(), p_user_id)
              )
            )
          )
          or
          (
            c.kind in ('group','channel')
            and private.is_conversation_admin(c.id, auth.uid())
            and exists (
              select 1 from public.contact_requests r
              where r.status = 'accepted'
                and ((r.sender_id = auth.uid() and r.recipient_id = p_user_id)
                  or (r.recipient_id = auth.uid() and r.sender_id = p_user_id))
            )
            and not private.are_users_blocked(auth.uid(), p_user_id)
          )
        )
    );
$$;
revoke all on function private.can_add_direct_member(uuid,uuid) from public, anon;
grant execute on function private.can_add_direct_member(uuid,uuid) to authenticated;

drop policy if exists "authorized users add members" on public.conversation_members;
create policy "authorized users add members" on public.conversation_members
  for insert to authenticated with check (
    private.can_add_direct_member(conversation_id, user_id)
    or (
      user_id = (select auth.uid()) and exists (
        select 1 from public.conversations c
        where c.id = conversation_id and c.kind = 'channel' and c.is_public = true
          and not private.are_users_blocked(auth.uid(), c.created_by)
      )
    )
  );

create or replace function private.guard_message_receipt_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.message_id is distinct from old.message_id
     or new.user_id is distinct from old.user_id
     or new.user_id <> auth.uid() then
    raise exception 'message receipt identity is immutable';
  end if;
  if old.read_at is not null and new.read_at is distinct from old.read_at then
    new.read_at := old.read_at;
  end if;
  if old.delivered_at is not null and new.delivered_at is distinct from old.delivered_at then
    new.delivered_at := old.delivered_at;
  end if;
  return new;
end;
$$;
revoke all on function private.guard_message_receipt_update() from public, anon, authenticated;
drop trigger if exists message_receipts_guard_update on public.message_receipts;
create trigger message_receipts_guard_update
before update on public.message_receipts
for each row execute function private.guard_message_receipt_update();

create or replace function private.guard_pinned_message()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.messages m
    where m.id = new.message_id and m.conversation_id = new.conversation_id
  ) then
    raise exception 'pinned_message_must_belong_to_conversation';
  end if;
  if new.pinned_by <> auth.uid() then
    raise exception 'pinned_by_must_match_current_user';
  end if;
  return new;
end;
$$;
revoke all on function private.guard_pinned_message() from public, anon, authenticated;
drop trigger if exists pinned_messages_guard_insert on public.pinned_messages;
create trigger pinned_messages_guard_insert
before insert on public.pinned_messages
for each row execute function private.guard_pinned_message();

create or replace function public.transfer_conversation_ownership(
  p_conversation_id uuid, p_new_owner_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if p_new_owner_id = auth.uid() then raise exception 'new_owner_must_be_another_member'; end if;
  if not exists (
    select 1 from public.conversations c
    join public.conversation_members m on m.conversation_id = c.id
    where c.id = p_conversation_id and c.kind in ('group','channel')
      and m.user_id = auth.uid() and m.role = 'owner'
  ) then raise exception 'only_current_owner_can_transfer'; end if;
  if not exists (
    select 1 from public.conversation_members m
    where m.conversation_id = p_conversation_id and m.user_id = p_new_owner_id
  ) then raise exception 'new_owner_must_be_member'; end if;

  update public.conversation_members set role = 'admin'
    where conversation_id = p_conversation_id and user_id = auth.uid();
  update public.conversation_members set role = 'owner'
    where conversation_id = p_conversation_id and user_id = p_new_owner_id;
  update public.conversations set updated_at = now() where id = p_conversation_id;
end;
$$;
revoke all on function public.transfer_conversation_ownership(uuid,uuid) from public, anon;
grant execute on function public.transfer_conversation_ownership(uuid,uuid) to authenticated;
