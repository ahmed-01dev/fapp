-- WASEL backend foundation: device registration and safety controls.
-- Apply only to a dedicated WASEL Supabase project after reviewing the migration.
-- No service-role credentials or provider secrets are stored in these tables.

create table if not exists public.device_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null check (char_length(token) between 20 and 4096),
  platform text not null check (platform in ('android', 'ios')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  disabled_at timestamptz,
  unique (token)
);
create index if not exists device_push_tokens_user_active_idx
  on public.device_push_tokens(user_id, updated_at desc)
  where disabled_at is null;

alter table public.device_push_tokens enable row level security;
revoke all on public.device_push_tokens from anon, public;
grant select, insert, update, delete on public.device_push_tokens to authenticated;

drop policy if exists "users read own push devices" on public.device_push_tokens;
create policy "users read own push devices"
  on public.device_push_tokens for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "users register own push devices" on public.device_push_tokens;
create policy "users register own push devices"
  on public.device_push_tokens for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "users update own push devices" on public.device_push_tokens;
create policy "users update own push devices"
  on public.device_push_tokens for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists "users remove own push devices" on public.device_push_tokens;
create policy "users remove own push devices"
  on public.device_push_tokens for delete to authenticated
  using (user_id = (select auth.uid()));

create table if not exists public.user_blocks (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index if not exists user_blocks_blocked_idx
  on public.user_blocks(blocked_id, blocker_id);

alter table public.user_blocks enable row level security;
revoke all on public.user_blocks from anon, public;
grant select, insert, delete on public.user_blocks to authenticated;

drop policy if exists "users read their own blocks" on public.user_blocks;
create policy "users read their own blocks"
  on public.user_blocks for select to authenticated
  using (blocker_id = (select auth.uid()));

drop policy if exists "users create their own blocks" on public.user_blocks;
create policy "users create their own blocks"
  on public.user_blocks for insert to authenticated
  with check (blocker_id = (select auth.uid()));

drop policy if exists "users remove their own blocks" on public.user_blocks;
create policy "users remove their own blocks"
  on public.user_blocks for delete to authenticated
  using (blocker_id = (select auth.uid()));

create table if not exists public.user_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reported_user_id uuid references auth.users(id) on delete set null,
  message_id uuid references public.messages(id) on delete set null,
  reason text not null check (reason in (
    'spam', 'harassment', 'impersonation', 'scam', 'unsafe_content', 'other'
  )),
  details text check (details is null or char_length(details) <= 2000),
  status text not null default 'open' check (status in ('open', 'reviewing', 'resolved', 'dismissed')),
  created_at timestamptz not null default now(),
  check (reported_user_id is not null or message_id is not null)
);
create index if not exists user_reports_status_created_idx
  on public.user_reports(status, created_at desc);

alter table public.user_reports enable row level security;
revoke all on public.user_reports from anon, public;
grant select, insert on public.user_reports to authenticated;

drop policy if exists "users create own abuse reports" on public.user_reports;
create policy "users create own abuse reports"
  on public.user_reports for insert to authenticated
  with check (reporter_id = (select auth.uid()) and status = 'open');

drop policy if exists "users read only their own reports" on public.user_reports;
create policy "users read only their own reports"
  on public.user_reports for select to authenticated
  using (reporter_id = (select auth.uid()));

-- Moderation status changes are intentionally unavailable to client roles.
