# WASEL — واصل

Cross-platform messaging app foundation for Android and iOS. Working product name: WASEL; final brand name can be changed later.

## MVP scope
- Phone-number-only SMS OTP authentication using E.164.
- Unique optional username, searchable without exposing phone numbers.
- 1:1 conversations and realtime text messages.
- Nearby is strictly opt-in, off by default, approximate-distance only, and backed by short-lived presence records.
- Arabic RTL + English, light/dark themes.

Not included yet: Signal Protocol E2EE, media upload, group/channel administration, WebRTC calls, bots, stories, scheduled messages, and multi-device cloud sync. These require separate security and infrastructure milestones.

## Architecture
- Mobile: Flutter, Material 3, Supabase Flutter client.
- Auth: Supabase Auth phone OTP with an SMS provider configured in the dashboard. Never put provider secrets in the app.
- API/data: PostgreSQL with RLS; Supabase Realtime for message updates.
- Nearby: private PostGIS-backed presence table and RPCs. Exact coordinates are never returned to clients; results expose only a coarse distance band. Presence expires after 30 minutes.
- Files later: private S3-compatible storage with signed, short-lived URLs and server-side size/type validation.
- Calls later: WebRTC with TURN; push via FCM/APNs.

## Run locally
1. Install Flutter stable and create platform folders if absent: flutter create --platforms=android,ios .
2. Copy .env.example to .env and set Supabase project URL and publishable key.
3. Run flutter pub get.
4. Review and run database/schema.sql in the Supabase SQL Editor.
5. In Supabase Auth, enable Phone provider, configure an SMS provider, set OTP expiry/rate limits, and enable CAPTCHA/abuse protection before public testing.
6. Explicitly expose required tables to the Data API and apply the grants/RLS from the SQL script.
7. Run with --dart-define=SUPABASE_URL=... and --dart-define=SUPABASE_PUBLISHABLE_KEY=...

No service-role key belongs in a mobile app. Do not commit real credentials or production user data.

## Important security notes
- Phone visibility defaults to contacts; phone-number search is not implemented until a consent-aware discovery endpoint exists.
- Nearby is off by default. The client must request explicit opt-in before location permission or updates.
- Username uniqueness is enforced by a case-insensitive unique index.
- Text chat in this foundation is not end-to-end encrypted yet. Do not market it as E2EE until audited Signal Protocol sessions, identity/key backup, device verification, and attachment encryption are implemented.
