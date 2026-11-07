-- WASEL conversation lifecycle and discoverable channels.
grant update on public.conversations to authenticated;

create or replace function private.add_creator_to_conversation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.conversation_members(conversation_id, user_id, role)
  values (new.id, new.created_by, 'owner')
  on conflict (conversation_id, user_id) do update set role = 'owner';
  return new;
end;
$$;
revoke all on function private.add_creator_to_conversation() from public, anon, authenticated;

drop policy if exists "members or public users read conversations" on public.conversations;
create policy "members or public users read conversations" on public.conversations
  for select to authenticated using (
    is_public = true or private.is_conversation_member(id, (select auth.uid()))
  );

drop policy if exists "users join public channels" on public.conversation_members;
create policy "users join public channels" on public.conversation_members
  for insert to authenticated with check (
    user_id = (select auth.uid()) and exists (
      select 1 from public.conversations c
      where c.id = conversation_id and c.kind = 'channel' and c.is_public = true
    )
  );

create or replace function public.create_group(p_title text, p_member_ids uuid[] default '{}')
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare new_id uuid; member_count integer;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if p_title is null or char_length(trim(p_title)) not between 1 and 80 then
    raise exception 'invalid_group_title';
  end if;
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
declare new_id uuid; normalized_username text;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if p_title is null or char_length(trim(p_title)) not between 1 and 80 then
    raise exception 'invalid_channel_title';
  end if;
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

do $$
begin
  alter publication supabase_realtime add table public.conversations;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.conversation_members;
exception when duplicate_object then null;
end $$;
