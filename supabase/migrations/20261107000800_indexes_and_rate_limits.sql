-- WASEL indexes and abuse limits for conversation creation.
create index if not exists message_reactions_user_idx on public.message_reactions(user_id);
create index if not exists message_receipts_user_idx on public.message_receipts(user_id);
create index if not exists pinned_messages_message_idx on public.pinned_messages(message_id);
create index if not exists pinned_messages_pinned_by_idx on public.pinned_messages(pinned_by);
create index if not exists typing_presence_user_idx on public.typing_presence(user_id);

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
security definer
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
