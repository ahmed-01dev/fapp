-- WASEL E2EE public-key directory.
-- This stores public key material only. Private keys must remain on user devices.
create table if not exists public.user_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_label text not null default 'Device' check (char_length(device_label) between 1 and 40),
  identity_key text not null check (char_length(identity_key) between 40 and 4096),
  registration_id integer not null check (registration_id between 1 and 2147483647),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  revoked_at timestamptz,
  unique(user_id, registration_id)
);
create index if not exists user_devices_user_active_idx
  on public.user_devices(user_id, created_at desc) where revoked_at is null;

create table if not exists public.device_signed_prekeys (
  device_id uuid primary key references public.user_devices(id) on delete cascade,
  key_id integer not null check (key_id >= 0),
  public_key text not null check (char_length(public_key) between 40 and 4096),
  signature text not null check (char_length(signature) between 40 and 4096),
  created_at timestamptz not null default now()
);

create table if not exists public.device_one_time_prekeys (
  id bigint generated always as identity primary key,
  device_id uuid not null references public.user_devices(id) on delete cascade,
  key_id integer not null check (key_id >= 0),
  public_key text not null check (char_length(public_key) between 40 and 4096),
  created_at timestamptz not null default now(),
  unique(device_id, key_id)
);
create index if not exists device_one_time_prekeys_device_idx
  on public.device_one_time_prekeys(device_id, id);

alter table public.user_devices enable row level security;
alter table public.device_signed_prekeys enable row level security;
alter table public.device_one_time_prekeys enable row level security;

revoke all on public.user_devices, public.device_signed_prekeys, public.device_one_time_prekeys from anon, public;
grant select, insert, update, delete on public.user_devices to authenticated;
grant select, insert, update, delete on public.device_signed_prekeys to authenticated;
grant select, insert, delete on public.device_one_time_prekeys to authenticated;

drop policy if exists "users manage their own devices" on public.user_devices;
create policy "users manage their own devices" on public.user_devices
for all to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists "authenticated users read active device public keys" on public.user_devices;
create policy "authenticated users read active device public keys" on public.user_devices
for select to authenticated using (revoked_at is null);

drop policy if exists "device owners manage signed prekeys" on public.device_signed_prekeys;
create policy "device owners manage signed prekeys" on public.device_signed_prekeys
for all to authenticated
using (exists (select 1 from public.user_devices d where d.id = device_id and d.user_id = (select auth.uid())))
with check (exists (select 1 from public.user_devices d where d.id = device_id and d.user_id = (select auth.uid())));

drop policy if exists "authenticated users read signed prekeys" on public.device_signed_prekeys;
create policy "authenticated users read signed prekeys" on public.device_signed_prekeys
for select to authenticated using (
  exists (select 1 from public.user_devices d where d.id = device_id and d.revoked_at is null)
);

drop policy if exists "device owners manage one time prekeys" on public.device_one_time_prekeys;
create policy "device owners manage one time prekeys" on public.device_one_time_prekeys
for all to authenticated
using (exists (select 1 from public.user_devices d where d.id = device_id and d.user_id = (select auth.uid())))
with check (exists (select 1 from public.user_devices d where d.id = device_id and d.user_id = (select auth.uid())));

create or replace function private.consume_one_time_prekey(p_device_id uuid)
returns table(key_id integer, public_key text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  selected public.device_one_time_prekeys%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not exists (
    select 1 from public.user_devices d
    where d.id = p_device_id and d.revoked_at is null
  ) then
    raise exception 'device unavailable';
  end if;
  select * into selected
  from public.device_one_time_prekeys p
  where p.device_id = p_device_id
  order by p.id
  limit 1
  for update skip locked;
  if selected.id is null then
    return;
  end if;
  delete from public.device_one_time_prekeys p where p.id = selected.id;
  return query select selected.key_id, selected.public_key;
end;
$$;
revoke all on function private.consume_one_time_prekey(uuid) from public, anon;
grant execute on function private.consume_one_time_prekey(uuid) to authenticated;
