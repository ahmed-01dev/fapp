# WASEL deployment runbook

## Live Supabase project

- Project: `qxtqrdzvwncfvyvbevok`
- URL: `https://qxtqrdzvwncfvyvbevok.supabase.co`
- Region: `eu-west-1`
- Status at last verification: `ACTIVE_HEALTHY`
- This is the dedicated WASEL project. Never deploy WASEL migrations to NEXORA.

## Database

The following migrations have been applied to the live WASEL project and are recorded in Supabase migration history:

1. `20261106000100_wasel_core.sql`
2. `20261106000200_backend_foundation.sql`
3. `20261106000300_security_hardening.sql`
4. `20261107000100_media_and_call_signaling.sql`
5. `20261107000200_e2ee_key_directory.sql`
6. `20261107000300_groups_receipts_reactions.sql`
7. `20261107000400_conversation_lifecycle.sql`
8. `20261107000500_rich_message_media.sql`
9. `20261107000600_call_lifecycle_hardening.sql`
10. `20261107000700_security_policy_consolidation.sql` — consolidated RLS policies and device bundle retrieval.
11. `20261107000800_indexes_and_rate_limits.sql` — FK indexes and group/channel creation limits.
12. `20261107000900_media_mime_allowlist.sql` — common document MIME types.
13. `20261107001000_group_invite_safety.sql` — accepted-contact invitations and member removal controls.
14. `20261107001100_ownership_transfer.sql` — group/channel ownership transfer.
15. `20261107001200_reduce_rpc_privileges.sql` — converts exposed creation RPCs to invoker rights.
16. `20261107001300_user_presence.sql` — contact-scoped online and last-seen presence.
17. `20261107001400_e2ee_prekey_access_control.sql` — restricts public-key bundle fetches to accepted contacts/shared conversations.
18. `advisor_security_hardening` (live security adjustment)

The live database currently reports 19 public tables with RLS enabled, 9 public tables in the Realtime publication, and the private `chat-media` bucket. These are schema checks, not end-to-end user acceptance tests.

For future changes, add a new timestamped migration under `supabase/migrations/`, review it, apply it to WASEL only, and verify migration history and advisors.

## Deployed Edge Functions

- `health` — public liveness endpoint; JWT verification disabled intentionally.
- `account-bootstrap` — requires a valid user JWT.
- `push-dispatch` — requires a valid user JWT, verifies message ownership and recipient privacy, and dispatches generic FCM notifications.

Function status was verified as `ACTIVE`. Push delivery still requires Firebase project configuration, device token registration, and the server-side `FCM_SERVICE_ACCOUNT_JSON` secret. See [PROVIDER_SETUP.md](PROVIDER_SETUP.md).

## Flutter client configuration

Use only the Supabase project URL and publishable key in the app build:

```sh
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://qxtqrdzvwncfvyvbevok.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_SUPABASE_PUBLISHABLE_KEY
```

Never put the Supabase service-role key, database password, SMS provider credentials, FCM service-account JSON, or TURN credentials in Flutter, GitHub source, or a downloadable APK.

## Remaining production gates

- Configure and test real SMS OTP delivery.
- Complete Firebase client setup, register device tokens, and set `FCM_SERVICE_ACCOUNT_JSON`.
- Basic file picking, private upload, image preview, and signed file opening are wired; resumable/background uploads, in-app audio/video players, thumbnails, malware scanning, and quota controls remain.
- Integrate a maintained Signal Protocol client before claiming E2EE.
- Integrate Flutter WebRTC, TURN credentials, call UI, and background incoming-call handling.
- Add automated RLS tests using two separate authenticated accounts.
- Test blocking/reporting and all message/group/channel flows end to end.
- Review advisor warnings and performance indexes against actual query patterns.
- Add monitoring, backups, retention/deletion policies, rate limiting, and incident procedures.

## Free-tier boundary

This project uses Supabase-managed Postgres, Auth, Realtime, Storage, and Edge Functions. It does not have a separate always-on custom server. Free tiers have quotas, possible pausing, storage/egress limits, and no production SLA. SMS, TURN relay traffic, high media usage, and production-scale traffic may require paid services. Do not upgrade or incur charges without explicit approval.
