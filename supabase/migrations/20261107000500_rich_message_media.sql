-- WASEL rich message metadata and secure media references.
alter table public.messages alter column body drop not null;
alter table public.messages
  add column if not exists message_type text not null default 'text',
  add column if not exists media_path text,
  add column if not exists media_mime text,
  add column if not exists media_size bigint,
  add column if not exists reply_to uuid references public.messages(id) on delete set null;

alter table public.messages drop constraint if exists messages_body_check;
alter table public.messages add constraint messages_body_check
  check (body is null or char_length(body) <= 10000);
alter table public.messages drop constraint if exists messages_message_type_check;
alter table public.messages add constraint messages_message_type_check
  check (message_type in ('text','image','video','audio','file','location'));
alter table public.messages drop constraint if exists messages_media_size_check;
alter table public.messages add constraint messages_media_size_check
  check (media_size is null or media_size between 1 and 52428800);
alter table public.messages drop constraint if exists messages_media_metadata_check;
alter table public.messages add constraint messages_media_metadata_check
  check (
    (message_type = 'text' and media_path is null and media_mime is null and media_size is null)
    or
    (message_type in ('image','video','audio','file') and media_path is not null
      and media_mime is not null and media_size is not null)
    or
    (message_type = 'location' and media_path is null)
  );

create or replace function private.validate_message_payload()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.sender_id <> auth.uid() then
    raise exception 'sender_mismatch';
  end if;
  if new.reply_to is not null and not exists (
    select 1 from public.messages parent
    where parent.id = new.reply_to and parent.conversation_id = new.conversation_id
  ) then
    raise exception 'reply_target_not_in_conversation';
  end if;
  if new.message_type in ('image','video','audio','file') then
    if new.media_path !~ ('^' || new.conversation_id::text || '/' || new.sender_id::text || '/')
      or not exists (
        select 1 from storage.objects o
        where o.bucket_id = 'chat-media' and o.name = new.media_path
      ) then
      raise exception 'media_object_not_found_or_not_owned';
    end if;
  end if;
  if new.message_type = 'location' and new.body is null then
    raise exception 'location_payload_required';
  end if;
  return new;
end;
$$;
revoke all on function private.validate_message_payload() from public, anon, authenticated;
drop trigger if exists messages_validate_payload on public.messages;
create trigger messages_validate_payload
before insert on public.messages
for each row execute function private.validate_message_payload();

create index if not exists messages_reply_to_idx on public.messages(reply_to) where reply_to is not null;
