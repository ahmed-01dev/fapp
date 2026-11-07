# WASEL encryption implementation plan

This document is a status/engineering gate, not a claim that end-to-end encryption is already enabled.

## Current verified state

- Supabase has a public-device-key directory: `user_devices`, `device_signed_prekeys`, and `device_one_time_prekeys`.
- Authenticated key-bundle access is restricted by the deployed database functions and RLS.
- Message rows still use `messages.body` for plaintext. The Flutter send/load paths currently insert and read that field directly.
- WebRTC uses DTLS-SRTP between peer endpoints. TURN relays forward encrypted packets; they do not decrypt media.
- WASEL does not yet have app-level Signal identity verification, encrypted message payloads, or a separately negotiated FrameCryptor media key.

## Required implementation order

1. Select and security/license-review a maintained Signal Protocol implementation for Flutter. Do not write a custom X3DH/Double Ratchet implementation and do not adopt a package solely because its API compiles.
2. Implement durable stores for identity, session, signed-prekey, one-time-prekey, Kyber-prekey, and sender-key state. Persist atomically before releasing ciphertext/plaintext; serialize ratchet operations per remote device.
3. Generate device identity and registration IDs locally. Publish only public identity keys, signed prekeys, and one-time prekeys. Keep private keys in platform-protected local storage.
4. Fetch and verify recipient device bundles, establish sessions, and encrypt every text/media message before upload. Store ciphertext plus version/algorithm metadata; never upload plaintext message bodies.
5. Support multiple recipient devices, key changes, device revocation, safety-number verification, group sender-key distribution, and secure attachment encryption.
6. Keep push notifications generic; never include message plaintext or cryptographic secrets in notification payloads.
7. For calls, establish a fresh per-call media key through the authenticated end-to-end key agreement, then enable flutter_webrtc FrameCryptor on every sending and receiving audio/video track. Never hard-code a shared media key or derive it from public user IDs.
8. Keep WebRTC DTLS-SRTP enabled. TURN is a packet relay only; it does not replace E2EE key agreement.

## Release gates

- No plaintext message fallback for conversations marked encrypted.
- Test first-contact prekey messages, two-way ratchet progression, offline delivery, replay rejection, device linking/revocation, app restart, backup/restore rollback handling, and key-change warnings.
- Verify group membership changes and sender-key rotation.
- Verify call media encryption on both audio and video tracks, mismatched-key failure, key rotation on reconnect, and no plaintext media path.
- Run dependency/license review, static analysis, unit/integration tests, and two-device tests before publishing.
