-- WASEL group/channel ownership transfer before owner departure.
create or replace function private.can_remove_conversation_member(
  p_conversation_id uuid, p_target_user_id uuid, p_actor_user_id uuid
)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select p_actor_user_id is not null and (
    (
      p_target_user_id = p_actor_user_id
      and exists (select 1 from public.conversation_members m
        where m.conversation_id = p_conversation_id and m.user_id = p_actor_user_id)
      and (
        exists (select 1 from public.conversations c
          where c.id = p_conversation_id and c.kind = 'direct')
        or exists (select 1 from public.conversation_members m
          where m.conversation_id = p_conversation_id and m.user_id = p_actor_user_id
            and m.role <> 'owner')
      )
    )
    or exists (
      select 1 from public.conversation_members actor
      join public.conversation_members target
        on target.conversation_id = actor.conversation_id
      where actor.conversation_id = p_conversation_id
        and actor.user_id = p_actor_user_id
        and actor.role in ('owner','admin')
        and target.user_id = p_target_user_id
        and target.role <> 'owner'
        and (actor.role = 'owner' or target.role = 'member')
    )
  );
$$;
revoke all on function private.can_remove_conversation_member(uuid,uuid,uuid) from public, anon;
grant execute on function private.can_remove_conversation_member(uuid,uuid,uuid) to authenticated;

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
      and c.created_by = auth.uid() and m.user_id = auth.uid() and m.role = 'owner'
  ) then raise exception 'only_current_owner_can_transfer'; end if;
  if not exists (
    select 1 from public.conversation_members m
    where m.conversation_id = p_conversation_id and m.user_id = p_new_owner_id
  ) then raise exception 'new_owner_must_be_member'; end if;

  update public.conversation_members
    set role = 'admin'
    where conversation_id = p_conversation_id and user_id = auth.uid();
  update public.conversation_members
    set role = 'owner'
    where conversation_id = p_conversation_id and user_id = p_new_owner_id;
  update public.conversations
    set created_by = p_new_owner_id, updated_at = now()
    where id = p_conversation_id;
end;
$$;
revoke all on function public.transfer_conversation_ownership(uuid,uuid) from public, anon;
grant execute on function public.transfer_conversation_ownership(uuid,uuid) to authenticated;
