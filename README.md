# WASEL — واصل

Flutter messaging app foundation for Android and iOS. The dedicated Supabase backend is live; this is still an MVP under development, not a production WhatsApp/Telegram replacement.

## Live backend
- Supabase project: `qxtqrdzvwncfvyvbevok`
- URL: `https://qxtqrdzvwncfvyvbevok.supabase.co`
- Database migrations: 18 recorded entries including the initial baseline, safety hardening, groups/channels, media, calls, presence, and key-directory access controls.
- Edge Functions: `health`, `account-bootstrap`, `push-dispatch` (deployed and ACTIVE).
- 19 public tables with RLS enabled; 9 public tables in Realtime.
- Private `chat-media` Storage bucket with a 50 MiB limit.

Never deploy WASEL migrations to the NEXORA project.

## Implemented foundations
- Phone OTP screen and Supabase Auth integration; real SMS delivery still requires a configured SMS provider.
- Profile bootstrap, username search, contact requests and direct conversations.
- Realtime text chat, replies, edit/delete, reactions, pins, typing indicator, and read-receipt writes.
- Group and public channel creation/discovery foundations; basic group/channel chat.
- Private media upload, image preview, and signed file opening for common image/video/audio/document formats.
- Block/report controls for direct conversations and block-aware Nearby discovery.
- Expiring online/last-seen and Nearby presence.
- Call session/signaling schema and Flutter signaling service methods.
- Public device-key directory and one-time prekey bundle retrieval foundation.
- FCM dispatch Edge Function and Firebase Messaging client token registration code.

## Not yet production-complete
- Real SMS OTP requires provider setup and end-to-end testing.
- Push requires Firebase Android/iOS app configuration, APNs key for iOS, and Supabase secret `FCM_SERVICE_ACCOUNT_JSON`.
- WebRTC audio/video media, TURN relay, call UI, and incoming-call background handling are not implemented.
- Signal Protocol client encryption, secure persistent key stores, device verification, and encrypted backups are not implemented. Messages are currently not E2EE.
- Resumable/background media transfer, in-app audio/video players, thumbnails, malware scanning, and quotas remain.
- Group/channel administration, broadcast tools, stories, bots, and multi-device synchronization remain incomplete.
- Two-account RLS/realtime integration tests, moderation workflows, monitoring, backup/restore, retention and incident response remain.

## Run locally
1. Install Flutter stable.
2. Generate platform folders if absent: `flutter create --platforms=android,ios --org com.wasel.app .`
3. Run `flutter pub get`.
4. Supply the Supabase URL and publishable key with `--dart-define` values.
5. For Firebase push, follow [docs/PROVIDER_SETUP.md](docs/PROVIDER_SETUP.md).
6. Run `flutter analyze` and `flutter test`.

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md), [docs/FREE_BACKEND_PLAN.md](docs/FREE_BACKEND_PLAN.md), and [docs/PROVIDER_SETUP.md](docs/PROVIDER_SETUP.md).

## Security
- Never ship service-role keys, database passwords, SMS credentials, Firebase service-account JSON, or TURN secrets in the app.
- RLS is enabled on all current public tables.
- Nearby is opt-in and exposes only coarse distance bands, never raw coordinates.
- Do not claim end-to-end encryption until an audited Signal Protocol client and secure key lifecycle are implemented and tested.
