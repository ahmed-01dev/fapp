-- WASEL security policy consolidation and public-key bundle retrieval.
-- Consolidate overlapping permissive policies without changing intended access.

drop policy if exists "conversation members can read conversation" on public.conversations;
drop policy if exists "members or public users read conversations" on public.conversations;
create policy "members or public users read conversations" on public.conversations
  for select to authenticated using (
    is_public = true or private.is_conversation_member(id, (select auth.uid()))
  );

drop policy if exists "admins add members" on public.conversation_members;
drop policy if exists "users join public channels" on public.conversation_members;
create policy "authorized users add members" on public.conversation_members
  for insert to authenticated with check (
    private.can_add_direct_member(conversation_id, user_id)
    or (
      user_id = (select auth.uid()) and exists (
        select 1 from public.conversations c
        where c.id = conversation_id and c.kind = 'channel' and c.is_public = true
      )
    )
  );

drop policy if exists "members see typing presence" on public.typing_presence;
drop policy if exists "users manage own typing presence" on public.typing_presence;
create policy "members see typing presence" on public.typing_presence
  for select to authenticated using (private.is_conversation_member(conversation_id, (select auth.uid())));
create policy "users create own typing presence" on public.typing_presence
  for insert to authenticated with check (
    user_id = (select auth.uid()) and private.is_conversation_member(conversation_id, (select auth.uid()))
  );
create policy "users update own typing presence" on public.typing_presence
  for update to authenticated using (
    user_id = (select auth.uid()) and private.is_conversation_member(conversation_id, (select auth.uid()))
  ) with check (
    user_id = (select auth.uid()) and private.is_conversation_member(conversation_id, (select auth.uid()))
  );
create policy "users delete own typing presence" on public.typing_presence
  for delete to authenticated using (user_id = (select auth.uid()));

drop policy if exists "users manage their own devices" on public.user_devices;
drop policy if exists "authenticated users read active device public keys" on public.user_devices;
create policy "read active device public keys" on public.user_devices
  for select to authenticated using (revoked_at is null or user_id = (select auth.uid()));
create policy "users insert own devices" on public.user_devices
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "users update own devices" on public.user_devices
  for update to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "users delete own devices" on public.user_devices
  for delete to authenticated using (user_id = (select auth.uid()));

drop policy if exists "device owners manage signed prekeys" on public.device_signed_prekeys;
drop policy if exists "authenticated users read signed prekeys" on public.device_signed_prekeys;
create policy "read active signed prekeys" on public.device_signed_prekeys
  for select to authenticated using (
    exists (select 1 from public.user_devices d
      where d.id = device_id and (d.revoked_at is null or d.user_id = (select auth.uid())))
  );
create policy "owners insert signed prekeys" on public.device_signed_prekeys
  for insert to authenticated with check (
    exists (select 1 from public.user_devices d where d.id = device_id and d.user_id = (select auth.uid()))
  );
create policy "owners update signed prekeys" on public.device_signed_prekeys
  for update to authenticated using (
    exists (select 1 from public.user_devices d where d.id = device_id and d.user_id = (select auth.uid()))
  ) with check (
    exists (select 1 from public.user_devices d where d.id = device_id and d.user_id = (select auth.uid()))
  );
create policy "owners delete signed prekeys" on public.device_signed_prekeys
  for delete to authenticated using (
    exists (select 1 from public.user_devices d where d.id = device_id and d.user_id = (select auth.uid()))
  );

drop policy if exists "nearby presence is RPC only" on public.nearby_presence;
create policy "nearby presence is RPC only" on public.nearby_presence
  for all to authenticated using (false) with check (false);

create or replace function private.guard_conversation_identity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id <> old.id or new.kind <> old.kind
    or new.created_by <> old.created_by or new.created_at <> old.created_at then
    raise exception 'conversation identity fields are immutable';
  end if;
  if new.kind <> 'channel' and (new.is_public or new.username is not null) then
    raise exception 'only channels can be public or have a username';
  end if;
  return new;
end;
$$;
revoke all on function private.guard_conversation_identity() from public, anon, authenticated;
drop trigger if exists conversations_guard_identity on public.conversations;
create trigger conversations_guard_identity
before update on public.conversations
for each row execute function private.guard_conversation_identity();

alter table public.messages drop constraint if exists messages_media_metadata_check;
alter table public.messages add constraint messages_media_metadata_check
  check (
    (message_type = 'text' and body is not null and char_length(body) between 1 and 10000
      and media_path is null and media_mime is null and media_size is null)
    or
    (message_type in ('image','video','audio','file') and media_path is not null
      and media_mime is not null and media_size is not null)
    or
    (message_type = 'location' and body is not null and media_path is null)
  );

create or replace function public.fetch_device_bundle(p_device_id uuid)
returns table(
  device_id uuid,
  user_id uuid,
  registration_id integer,
  identity_key text,
  signed_prekey_id integer,
  signed_prekey text,
  signed_prekey_signature text,
  one_time_prekey_id integer,
  one_time_prekey text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  device_row public.user_devices%rowtype;
  signed_row public.device_signed_prekeys%rowtype;
  one_time_row public.device_one_time_prekeys%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  select * into device_row from public.user_devices d
    where d.id = p_device_id and d.revoked_at is null;
  if device_row.id is null then raise exception 'device_unavailable'; end if;
  select * into signed_row from public.device_signed_prekeys s
    where s.device_id = p_device_id;
  if signed_row.device_id is null then raise exception 'signed_prekey_unavailable'; end if;
  select * into one_time_row from public.device_one_time_prekeys p
    where p.device_id = p_device_id order by p.id limit 1 for update skip locked;
  if one_time_row.id is not null then
    delete from public.device_one_time_prekeys p where p.id = one_time_row.id;
  end if;
  return query select device_row.id, device_row.user_id, device_row.registration_id,
    device_row.identity_key, signed_row.key_id, signed_row.public_key, signed_row.signature,
    one_time_row.key_id, one_time_row.public_key;
end;
$$;
revoke all on function public.fetch_device_bundle(uuid) from public, anon;
grant execute on function public.fetch_device_bundle(uuid) to authenticated;
