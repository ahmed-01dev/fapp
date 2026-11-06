# WASEL backend deployment runbook

This repository contains backend source and migrations. Nothing in this document means a cloud project has already been created or deployed.

## 1. Required project boundary

Create a dedicated Supabase project named WASEL in a separate WASEL organization. Do not link this repository to the existing NEXORA project. Keep the project on a $0 plan; stop if the dashboard quotes any non-zero charge and obtain explicit approval before proceeding.

Choose a region close to the primary users (Frankfurt / eu-central-1 is the current recommendation for Egypt). Region choice does not guarantee latency or availability.

## 2. Local prerequisites

Install the Supabase CLI and Flutter SDK. From the repository root:

```sh
supabase --version
flutter --version
supabase login
supabase link --project-ref YOUR_WASEL_PROJECT_REF
```

Never commit access tokens, database passwords, service-role keys, SMS credentials, or push-provider private keys.

## 3. Database deployment

Review the SQL before applying it. Apply the baseline schema first, then the additive foundation migration:

```sh
supabase db push
```

For a fresh project, place the reviewed SQL in timestamped files under `supabase/migrations/` (or use the dashboard SQL editor in the documented order). The repository's current source-of-truth files are:

- `database/schema.sql`
- `database/2026_11_backend_foundation.sql`

Do not apply either file to NEXORA. After deployment, verify RLS is enabled on every client-facing table, verify the `messages` table is in `supabase_realtime`, and test access using two normal authenticated accounts.

## 4. Edge Functions

The repository config sets JWT verification off only for the public liveness endpoint. Account bootstrap requires a valid JWT.

```sh
supabase functions deploy health
supabase functions deploy account-bootstrap
```

Smoke test the health endpoint:

```sh
curl --fail --silent --show-error https://YOUR_WASEL_PROJECT_REF.supabase.co/functions/v1/health
```

Expected response includes `"status":"ok"`. This checks function liveness only; it does not prove database, authentication, realtime, push, or media are production-ready.

## 5. Flutter client configuration

Use only the project URL and publishable key in the client build:

```sh
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://YOUR_WASEL_PROJECT_REF.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_SUPABASE_PUBLISHABLE_KEY
```

The publishable key is intended for client use and is not a substitute for RLS. Never pass a service-role key to Flutter or GitHub Actions build arguments.

## 6. Mandatory verification before inviting users

- Phone Auth provider and SMS delivery are configured and tested; SMS may incur per-message charges.
- RLS tests prove one user cannot read another user's private conversations, messages, device tokens, blocks, or reports.
- Realtime delivers only rows the subscriber is authorized to read.
- Nearby is opt-in, expires automatically, and never returns raw coordinates.
- Abuse reporting and blocking are available in the client before public discovery.
- Storage buckets are private and signed URL access is scoped to the owner / conversation.
- Push tokens are registered securely; no push delivery is claimed until FCM/APNs are configured.
- The app clearly states that messages are not end-to-end encrypted until an audited Signal Protocol implementation and key lifecycle exist.

## 7. Current scope boundary

This deployment uses Supabase-managed services; it does not create a separate always-on Node.js/Go server. The current codebase does not yet implement media upload, push delivery, WebRTC calls, group conversations, background workers, or end-to-end encryption. Free-tier quotas, pausing, storage, and egress limits apply.
