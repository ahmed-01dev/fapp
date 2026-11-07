# WASEL — zero-budget backend plan and live status

## Live deployment
The dedicated WASEL Supabase project is deployed:
- Project ref: `qxtqrdzvwncfvyvbevok`
- URL: `https://qxtqrdzvwncfvyvbevok.supabase.co`
- Region: `eu-west-1`
- State at last check: `ACTIVE_HEALTHY`

Do not deploy to the NEXORA project.

## What is deployed
- Postgres schema for profiles, direct conversations, groups/channels, members, messages, receipts, reactions, pins, typing presence, contact requests, blocks, reports, nearby presence, push token registry, call sessions/signaling, and device public-key directory.
- RLS is enabled on all 18 current public tables.
- Realtime publication includes 8 public tables.
- Private `chat-media` Storage bucket with 50 MiB object limit and MIME allowlist.
- Edge Functions: `health`, `account-bootstrap`, `push-dispatch`.
- Database RPCs for Nearby, group creation and channel creation.
- Flutter service methods for text, group/channel lifecycle, media upload/signed URLs, receipts, reactions, pins, typing presence, and device-token registration.

## Not yet production-complete
| Feature | Live state |
|---|---|
| Basic text send/read | Flutter and Supabase integration exists; two-device acceptance test still required |
| Realtime messages | Schema publication and stream client exist; two-account RLS/realtime tests required |
| Groups/channels | Database lifecycle/RPCs exist; complete UI, discovery, moderation and tests remain |
| Read receipts | Tables and basic client write path exist; delivered/read UI and robust realtime updates remain |
| Media | Private bucket and upload/signed URL service methods exist; picker/player/resumable UI and malware controls remain |
| Push | Dispatch function deployed; Firebase client, device token acquisition and service-account secret still required |
| OTP | UI flow exists; SMS provider and real Egyptian number test still required |
| Calls | Signaling schema exists; WebRTC client, TURN, background call UX and tests not implemented |
| E2EE | Public-key directory exists only; Signal Protocol, client crypto and secure key lifecycle not implemented |
| Operations | Monitoring, scheduled cleanup, backups, abuse response and production runbooks remain |

## Cost and safety boundaries
- Keep the prototype on a genuinely $0 plan; do not upgrade or incur charges without explicit approval.
- Supabase free tiers have quotas, pausing/inactivity rules, storage/egress limits, and no production SLA.
- SMS delivery is not assumed free.
- TURN relay bandwidth and high media storage/egress are not assumed free.
- Never ship service-role keys, database passwords, Firebase service-account JSON, SMS credentials, or TURN secrets in Flutter.
- Do not describe messages as end-to-end encrypted until audited client-side cryptography is deployed and verified.

## Immediate remaining work
1. Configure Firebase/FCM and APNs; set `FCM_SERVICE_ACCOUNT_JSON` as a Supabase Edge Function secret.
2. Add Firebase client SDK initialization and automatic device token registration/refresh.
3. Finish the media attachment picker/player and background upload.
4. Implement and test Signal Protocol encryption.
5. Implement WebRTC voice/video calls and TURN.
6. Add integration tests for two authenticated users, blocking, reports, groups, channels, receipts, storage access and call state transitions.
7. Add moderation workflows, rate limits, monitoring, cleanup jobs and backups.

See [DEPLOYMENT.md](DEPLOYMENT.md) and [PROVIDER_SETUP.md](PROVIDER_SETUP.md).
