# WASEL Architecture

## System overview
Flutter iOS/Android client connects to Supabase Auth for phone OTP, PostgREST for profiles/conversations/messages, Realtime for message updates, and private Nearby RPCs for opt-in location heartbeats. Supabase hosts PostgreSQL with RLS, Realtime, and a private PostGIS schema. Media storage and call signaling are later phases.

## Domain model
- profiles: one public profile per auth user; username optional and unique case-insensitively. Phone visibility is an enum: everyone, contacts, nobody. Phone numbers are never included in public profile reads.
- conversations: direct conversations only in MVP.
- conversation_members: membership and authorization boundary.
- messages: text-only MVP with sender, body, timestamps and soft-delete metadata.
- nearby_presence in a private schema: one ephemeral geography per user, opt-in flag, expiry timestamp. Not exposed through the Data API.
- contact_requests and blocks in next milestone: strangers must accept a request before message delivery; blocks override every discovery and messaging path.

## Key flows
1. Sign-in: normalize phone to E.164, request SMS OTP, verify, then create profile row from auth.uid().
2. Username: validate 3–24 chars using a-z, 0-9, underscore and dot; unique index on lower(username); public search returns only safe profile fields.
3. Direct chat: create or reuse direct conversation, add both members, insert text message. RLS verifies sender membership on every operation.
4. Nearby: feature starts disabled. User explicitly enables it, grants foreground location permission, and sends limited heartbeats only while active. Server returns username/display name and a distance band such as within_500m, never coordinates or exact meters. Disable action deletes presence immediately.

## Security and privacy
- Enable RLS on every exposed table. Grant only required operations to authenticated role.
- Use auth.uid() ownership and membership predicates; authenticated role alone is not authorization.
- Keep nearby storage in a non-exposed schema. Private RPC functions validate auth.uid(), return no coordinate columns, and have EXECUTE revoked from PUBLIC.
- Nearby heartbeat TTL is 30 minutes; cleanup can run on a scheduled database job. Queries always ignore expired records.
- Nearby must not run in background in MVP. No history or tracking trail is retained.
- Apply per-user request limits at an edge/API layer before public launch; database constraints alone do not prevent SMS abuse.
- Never ship service-role keys, SMS provider credentials, TURN credentials, or storage secrets in the mobile bundle.

## Encryption boundary
MVP transport uses TLS and Supabase-managed encryption at rest. This is not E2EE. A later security milestone must integrate a maintained Signal Protocol implementation with per-device identity keys, signed prekeys, one-time prekeys, session state, safety-number/device verification, encrypted local storage, and encrypted media. Do not invent a home-grown cryptographic protocol.

## Scale path
- Start with PostgreSQL indexes and Supabase Realtime.
- Add Redis for presence fan-out, rate limiting, and hot ephemeral state when load justifies it.
- Move media to private S3-compatible storage and signed URLs.
- Add a dedicated signaling service and TURN for WebRTC.
- Split notification delivery into FCM/APNs worker with idempotent queues.
