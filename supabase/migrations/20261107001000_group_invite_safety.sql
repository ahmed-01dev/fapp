-- WASEL group invitation consent and moderation-safe member removal.
create or replace function private.can_add_direct_member(p_conversation_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
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
          (c.kind in ('group','channel') and private.is_conversation_admin(c.id, auth.uid())
            and exists (
              select 1 from public.contact_requests r
              where r.status = 'accepted'
                and ((r.sender_id = auth.uid() and r.recipient_id = p_user_id)
                  or (r.recipient_id = auth.uid() and r.sender_id = p_user_id))
            )
            and not exists (
              select 1 from public.user_blocks b
              where (b.blocker_id = auth.uid() and b.blocked_id = p_user_id)
                 or (b.blocker_id = p_user_id and b.blocked_id = auth.uid())
            ))
        )
    );
$$;
revoke all on function private.can_add_direct_member(uuid,uuid) from public, anon;
grant execute on function private.can_add_direct_member(uuid,uuid) to authenticated;

create or replace function public.create_group(p_title text, p_member_ids uuid[] default '{}')
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare new_id uuid; member_count integer; recent_count integer;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if p_title is null or char_length(trim(p_title)) not between 1 and 80 then
    raise exception 'invalid_group_title';
  end if;
  select count(*) into recent_count from public.conversations c
    where c.created_by = auth.uid() and c.kind = 'group'
      and c.created_at > now() - interval '1 hour';
  if recent_count >= 10 then raise exception 'group_creation_rate_limit'; end if;
  select count(distinct x) into member_count from unnest(coalesce(p_member_ids, '{}'::uuid[])) x
    where x <> auth.uid();
  if member_count > 199 then raise exception 'group_member_limit_exceeded'; end if;
  if exists (
    select 1 from unnest(coalesce(p_member_ids, '{}'::uuid[])) x
    where x <> auth.uid() and (
      not exists (
        select 1 from public.contact_requests r
        where r.status = 'accepted'
          and ((r.sender_id = auth.uid() and r.recipient_id = x)
            or (r.recipient_id = auth.uid() and r.sender_id = x))
      )
      or exists (
        select 1 from public.user_blocks b
        where (b.blocker_id = auth.uid() and b.blocked_id = x)
           or (b.blocker_id = x and b.blocked_id = auth.uid())
      )
    )
  ) then raise exception 'group_member_must_be_accepted_contact'; end if;
  insert into public.conversations(kind, created_by, title)
    values ('group', auth.uid(), trim(p_title)) returning id into new_id;
  insert into public.conversation_members(conversation_id, user_id)
    select new_id, x from unnest(coalesce(p_member_ids, '{}'::uuid[])) x
    where x <> auth.uid()
    on conflict do nothing;
  return new_id;
end;
$$;
revoke all on function public.create_group(text,uuid[]) from public, anon;
grant execute on function public.create_group(text,uuid[]) to authenticated;

create or replace function private.can_remove_conversation_member(
  p_conversation_id uuid, p_target_user_id uuid, p_actor_user_id uuid
)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select p_actor_user_id is not null and (
    p_target_user_id = p_actor_user_id
    or exists (
      select 1 from public.conversation_members actor
      join public.conversation_members target
        on target.conversation_id = actor.conversation_id
      join public.conversations c on c.id = actor.conversation_id
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

drop policy if exists "members may leave conversation" on public.conversation_members;
drop policy if exists "admins remove members or users leave" on public.conversation_members;
create policy "admins remove members or users leave" on public.conversation_members
  for delete to authenticated using (
    private.can_remove_conversation_member(conversation_id, user_id, (select auth.uid()))
  );
