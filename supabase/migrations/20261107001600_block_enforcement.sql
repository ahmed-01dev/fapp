-- Enforce blocks on new direct-chat messages, uploads, and calls.
create or replace function private.can_send_message(p_conversation_id uuid, p_user_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select p_user_id is not null
    and private.is_conversation_member(p_conversation_id, p_user_id)
    and (
      not exists (
        select 1 from public.conversations c
        where c.id = p_conversation_id and c.kind = 'direct'
      )
      or not exists (
        select 1
        from public.conversation_members other_member
        join public.user_blocks b
          on (b.blocker_id = p_user_id and b.blocked_id = other_member.user_id)
          or (b.blocker_id = other_member.user_id and b.blocked_id = p_user_id)
        where other_member.conversation_id = p_conversation_id
          and other_member.user_id <> p_user_id
      )
    );
$$;
revoke all on function private.can_send_message(uuid,uuid) from public, anon;
grant execute on function private.can_send_message(uuid,uuid) to authenticated;

drop policy if exists "members send as themselves" on public.messages;
create policy "unblocked members send as themselves" on public.messages
  for insert to authenticated with check (
    sender_id = (select auth.uid())
    and private.can_send_message(conversation_id, (select auth.uid()))
  );

drop policy if exists "chat media members upload own folder" on storage.objects;
create policy "unblocked chat members upload own folder"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'chat-media'
  and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
  and (storage.foldername(name))[2] = (select auth.uid())::text
  and private.can_send_message(
    ((storage.foldername(name))[1])::uuid,
    (select auth.uid())
  )
);

drop policy if exists "conversation member starts direct call" on public.call_sessions;
create policy "unblocked conversation member starts call"
on public.call_sessions for insert to authenticated
with check (
  caller_id = (select auth.uid())
  and private.can_send_message(conversation_id, (select auth.uid()))
  and private.can_send_message(conversation_id, callee_id)
);
