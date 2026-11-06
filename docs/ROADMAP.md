# Delivery Roadmap

## Phase 0 — foundation
- Flutter shell, Arabic/English direction, theme, OTP UI, profile/username, direct text chat, opt-in Nearby UI.
- PostgreSQL schema and RLS reference.
- No fake claims of E2EE, calls, or production SMS until configured and tested.

## Phase 1 — secure MVP
- Configure Supabase SMS provider, CAPTCHA, rate limits and phone normalization.
- Apply SQL in a staging project; test RLS as two separate users.
- Implement accepted contact requests and block/report before allowing stranger DMs.
- Add integration tests for OTP, username collisions, conversation membership, message authorization, Nearby opt-in/off and TTL expiry.
- Add app links, session restoration, secure local storage and crash reporting.

## Phase 2 — media and groups
- Private media bucket, signed URLs, upload validation, thumbnails and resumable uploads.
- Groups up to 1,000 members, roles, permissions, moderation and mute/report tools.
- Push notifications via FCM/APNs.

## Phase 3 — privacy and realtime features
- Audited Signal Protocol E2EE for 1:1 chats and secret chats; device verification and encrypted backups.
- WebRTC audio/video with TURN and call permission controls.
- Stories, channels, polls, reactions, scheduled/silent messages, folders, stickers.

## Phase 4 — platform
- Bot API with scoped tokens and sandboxing.
- Multi-device sync, abuse detection, data export/deletion, retention controls.
- Load tests, penetration test, privacy review and app-store compliance.

## Release gates
- No production launch with open RLS findings.
- No Nearby launch without opt-in UX, approximate-only output, TTL cleanup, block/report and abuse throttles.
