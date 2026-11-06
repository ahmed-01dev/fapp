# WASEL — Zero-budget backend plan

## Goal
Ship a real, secure MVP without renting a VPS. Use the existing Flutter client with Supabase-managed Postgres, Auth, Realtime, Storage and Edge Functions. GitHub Actions is build automation, not an application server.

## Cost boundary
- Keep the project on a genuinely $0 plan while prototyping.
- Never create or upgrade a paid Supabase project without the owner's explicit approval.
- Free tiers have quotas, inactivity/pausing rules, storage/egress limits and no production SLA. Re-check current plan limits before launch.
- SMS delivery is not assumed free. Phone OTP requires a supported provider and may incur per-message charges. Until configured, use a safe development-only auth flow; do not promise live SMS OTP.
- Push delivery requires FCM/APNs project setup. Provider setup may be free, but credentials and platform configuration are still required.
- TURN relay bandwidth, large media storage, and high-volume calls are not assumed to be free.

## Runtime map
| Concern | MVP implementation | Status |
|---|---|---|
| Database | Supabase Postgres + RLS | SQL source exists; not deployed to WASEL project |
| Identity | Supabase Auth | Client flow exists; SMS provider not configured |
| Realtime chat | Supabase Realtime + RLS | Client integration exists; publication must be verified after migration |
| API | Supabase Edge Functions (Deno) | Source added here; deployment requires selected WASEL project |
| Push | FCM/APNs + device token registry | Registry migration prepared; delivery integration pending credentials |
| Media | Private Supabase Storage bucket + signed URLs | Not implemented yet |
| Background jobs | Postgres scheduled jobs / Edge Function invocation | Not deployed; no always-on worker on free plan |
| Calls | WebRTC + external STUN/TURN | Not implemented; TURN may cost money |
| E2EE | Audited Signal Protocol implementation | Not implemented; current text messages are not E2EE |

## Deployment gate
The only Supabase project currently visible in the connected account is named `nexora`. It is not WASEL, so do not apply WASEL migrations or deploy WASEL functions there. Create/select a dedicated WASEL project first, verify its quoted cost is $0, then apply migrations and deploy functions.

## Release sequence
1. Select a dedicated free WASEL Supabase project.
2. Apply and verify database migrations; run security and performance advisors.
3. Deploy `health` and `account-bootstrap` Edge Functions.
4. Configure Auth providers and test sign-up/sign-in with real devices.
5. Configure private media storage and signed upload/download flows.
6. Add push delivery after FCM/APNs credentials are configured.
7. Add background cleanup/scheduled work with explicit quotas and monitoring.
8. Implement group messaging, receipts, calls and audited E2EE as separate milestones.

## Security rules
- Never ship service-role keys, database passwords, FCM private keys or SMS provider secrets in Flutter.
- All client-accessible tables must have RLS enabled and narrowly scoped policies.
- Edge Functions must validate the caller's access token and preserve the caller's RLS context unless a narrowly reviewed privileged operation is required.
- Do not describe the product as end-to-end encrypted until audited client-side encryption and key lifecycle are implemented.
- Nearby is opt-in, approximate-only, short-lived and must never expose raw coordinates to other users.
