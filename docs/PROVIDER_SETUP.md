# WASEL external provider setup

The WASEL Supabase project is live at `qxtqrdzvwncfvyvbevok`. Provider credentials are intentionally not committed to GitHub or embedded in the Flutter app.

## Push notifications (FCM for Android and iOS)

The authenticated `push-dispatch` and `call-dispatch` Edge Functions are deployed. `push-dispatch` handles new-message notifications; `call-dispatch` validates the authenticated caller and ringing call session, checks both block directions, and sends a short-lived generic incoming-call notification to the callee's active device tokens. It validates the caller, confirms the message belongs to that caller, excludes blocked recipients, fetches active device tokens, and sends generic notification text without exposing message contents.

### Required Firebase setup
1. In GitHub Actions, run **Generate Android platform files** once. It creates the Android project, adds microphone/camera/network/notification permissions, and configures the Google Services Gradle plugin to activate when `android/app/google-services.json` exists.
2. Create a Firebase project and register the Android app with application ID `com.wasel.app.wasel`. This is the expected ID from `flutter create --org com.wasel.app` for the package name `wasel`; keep it unchanged when registering the Firebase Android app.
3. Enable Firebase Cloud Messaging.
4. For iOS, register the iOS bundle ID and upload an APNs authentication key in Firebase Console.
5. The Flutter project already includes `firebase_core` and `firebase_messaging`, initializes Firebase when build-time configuration is supplied, requests notification permission, registers the FCM token with Supabase, and refreshes the token on rotation. Incoming-call push delivery is best-effort and requires the Android Firebase app registration, an installed build with the matching Firebase client configuration, a registered device token, and the server secret below. A push notification does not yet provide a full-screen native call UI or guarantee wake-up on every Android device.
6. Build with the platform-specific Firebase client values from Firebase Console. These client values are not service-account secrets:

```sh
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://qxtqrdzvwncfvyvbevok.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_SUPABASE_PUBLISHABLE_KEY \
  --dart-define=FIREBASE_API_KEY=YOUR_FIREBASE_API_KEY \
  --dart-define=FIREBASE_APP_ID=YOUR_ANDROID_FIREBASE_APP_ID \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=YOUR_SENDER_ID \
  --dart-define=FIREBASE_PROJECT_ID=YOUR_FIREBASE_PROJECT_ID
```

For an iOS build, use the iOS Firebase App ID and also pass `--dart-define=FIREBASE_IOS_BUNDLE_ID=YOUR_IOS_BUNDLE_ID`. Do not include a service-account private key in the app. On logout, the app disables the registered token; token refresh re-registers it.

### Server credential
Create a Firebase service account that has permission to send FCM messages. Store its complete JSON privately as a Supabase Edge Function secret, never in GitHub or Flutter:

```sh
supabase secrets set FCM_SERVICE_ACCOUNT_JSON="$(cat /secure/path/firebase-service-account.json)" --project-ref qxtqrdzvwncfvyvbevok
```

The Edge Function runtime provides the Supabase URL and service-role key. Confirm that `push-dispatch` returns a successful result with a real authenticated test account and a registered device token. Until Firebase setup and a token registration are complete, push delivery is not active even though the function is deployed.

## Phone OTP

Supabase Auth must have SMS enabled with a provider and a tested sender. SMS is not assumed free. Do not publish the app until a real Egyptian (+20) number can receive and verify an OTP. Keep rate limits and anti-abuse protections enabled.

## WebRTC calls

The database contains call sessions and participant-scoped signaling. A real calling client still requires:
- `flutter_webrtc` integration on Android/iOS;
- a STUN endpoint and a TURN relay with credentials;
- microphone/camera permissions and platform call lifecycle integration;
- foreground/background incoming-call handling and push wake-up;
- tests on Wi-Fi, mobile data, restrictive NAT, Bluetooth headsets, and app termination.

Do not place TURN credentials in public source. Prefer short-lived credentials from a server-side provider. TURN relay traffic may cost money.

## End-to-end encryption

The database key directory stores public device keys only. It is not an E2EE implementation. Before claiming E2EE:
- integrate a maintained, audited Signal Protocol implementation supported by the target platforms;
- generate and keep private identity/session keys on-device using platform secure storage;
- publish signed prekeys and one-time prekeys without exposing private material;
- encrypt/decrypt message bodies and attachments before upload;
- handle device linking, key changes, safety-number verification, key rotation, and encrypted backups;
- test replay, downgrade, device removal, multi-device delivery, and recovery.

Never invent a custom cryptographic protocol.

## Media

The private `chat-media` bucket is deployed with a 50 MiB limit and MIME allowlist. The Flutter service uploads bytes into the conversation/uploader path and returns short-lived signed URLs for viewing. A real picker/player UI, background/resumable upload, thumbnail generation, virus/content scanning, and quota enforcement remain separate tasks.

## Current live project
- Project ref: `qxtqrdzvwncfvyvbevok`
- Project URL: `https://qxtqrdzvwncfvyvbevok.supabase.co`
- Edge Functions: `health`, `account-bootstrap`, `push-dispatch`
- Do not use the older NEXORA project.
