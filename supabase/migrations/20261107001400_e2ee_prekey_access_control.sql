-- Prevent authenticated users from exhausting arbitrary users' one-time prekeys.
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

  if device_row.user_id <> auth.uid() and (
    private.are_users_blocked(auth.uid(), device_row.user_id)
    or not (
      exists (
        select 1 from public.contact_requests r
        where r.status = 'accepted'
          and ((r.sender_id = auth.uid() and r.recipient_id = device_row.user_id)
            or (r.recipient_id = auth.uid() and r.sender_id = device_row.user_id))
      )
      or exists (
        select 1 from public.conversation_members mine
        join public.conversation_members theirs
          on theirs.conversation_id = mine.conversation_id
        where mine.user_id = auth.uid() and theirs.user_id = device_row.user_id
      )
    )
  ) then
    raise exception 'device_unavailable';
  end if;

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
