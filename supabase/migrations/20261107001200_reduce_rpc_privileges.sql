-- Keep exposed creation RPCs SECURITY INVOKER; isolate block lookup in a private helper.
create or replace function private.are_users_blocked(p_user_a uuid, p_user_b uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.user_blocks b
    where (b.blocker_id = p_user_a and b.blocked_id = p_user_b)
       or (b.blocker_id = p_user_b and b.blocked_id = p_user_a)
  );
$$;
revoke all on function private.are_users_blocked(uuid,uuid) from public, anon;
grant execute on function private.are_users_blocked(uuid,uuid) to authenticated;

create or replace function public.create_group(p_title text, p_member_ids uuid[] default '{}')
returns uuid
language plpgsql
security invoker
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
      or private.are_users_blocked(auth.uid(), x)
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

create or replace function public.create_channel(p_title text, p_username text default null, p_description text default null)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare new_id uuid; normalized_username text; recent_count integer;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if p_title is null or char_length(trim(p_title)) not between 1 and 80 then
    raise exception 'invalid_channel_title';
  end if;
  select count(*) into recent_count from public.conversations c
    where c.created_by = auth.uid() and c.kind = 'channel'
      and c.created_at > now() - interval '1 day';
  if recent_count >= 3 then raise exception 'channel_creation_rate_limit'; end if;
  normalized_username := nullif(lower(trim(leading '@' from coalesce(p_username,''))), '');
  if normalized_username is not null and normalized_username !~ '^[a-z0-9_]{4,32}$' then
    raise exception 'invalid_channel_username';
  end if;
  insert into public.conversations(kind, created_by, title, description, is_public, username)
    values ('channel', auth.uid(), trim(p_title), left(nullif(trim(p_description),''), 500), true, normalized_username)
    returning id into new_id;
  return new_id;
end;
$$;
revoke all on function public.create_channel(text,text,text) from public, anon;
grant execute on function public.create_channel(text,text,text) to authenticated;
