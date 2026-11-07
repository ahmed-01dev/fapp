# WASEL calls — integration notes

## What this client now implements
- Audio and video call UI using `flutter_webrtc`.
- Peer-to-peer offer/answer and ICE candidate exchange using the existing private `call_sessions` and `call_signals` tables.
- Microphone mute, speaker/earpiece routing, camera toggle, camera switch, accept/reject, and hangup.
- Video calls default to speaker output; audio calls default to the earpiece. The in-call speaker button switches routes.
- Google STUN servers are configured as the initial free connectivity path.

## Required platform scaffold and permissions
The repository currently contains Flutter Dart sources but does not contain generated `android/` or `ios/` platform folders. Generate them from the project root before running on a device:

```sh
flutter create --platforms=android,ios --org com.wasel.app .
```

Android: add these permissions inside the top-level `<manifest>` element in `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-feature android:name="android.hardware.camera" />
<uses-feature android:name="android.hardware.camera.autofocus" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
```

iOS: add these keys inside `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>WASEL needs camera access for video calls.</string>
<key>NSMicrophoneUsageDescription</key>
<string>WASEL needs microphone access for calls.</string>
```

The plugin documentation lists the native permissions and platform requirements: https://flutter-webrtc.org/docs/flutter-webrtc/project-settings/

## TURN credential flow

The client calls the authenticated `call-ice-config` function for each active call. The function verifies call participation and returns a STUN fallback plus short-lived coturn REST credentials when `TURN_URLS` and `TURN_SHARED_SECRET` are configured. The TURN shared secret must remain in Supabase Edge Function secrets; never embed it in Flutter or GitHub.

## Encryption status

WebRTC already uses DTLS-SRTP for transport encryption. This is not the same as WASEL-managed end-to-end media encryption. The current call screen does not yet exchange a per-call media key or enable FrameCryptor, so do not claim media E2EE yet. The flutter_webrtc project documents a FrameCryptor API for a second E2EE layer, but it must receive a strong per-call key through an authenticated end-to-end key agreement, not a hard-coded shared password.

## Important current limitations
- The backend sends a high-priority FCM incoming-call notification, but native full-screen incoming-call UI and reliable answer/reject actions while the app is backgrounded or terminated are not implemented yet. This needs Android call-style notification/foreground-service integration and iOS CallKit/PushKit handling. On OPPO/ColorOS, autostart and battery restrictions also need device testing.
- Public STUN servers do not relay media. Some carrier, office, school, and symmetric-NAT networks require TURN. Until TURN is configured, a call may fail to connect on those networks.
- WebRTC media is protected in transit by DTLS-SRTP between the two peer endpoints; a TURN relay forwards encrypted packets and does not decrypt media. However, WASEL does not yet provide app-level peer identity verification or a separately negotiated FrameCryptor media key. Do not describe the call stack as having Signal-style identity-bound E2EE until that key agreement and verification are implemented and tested.
- A successful static build is not proof of real device-to-device operation. Test with two accounts on two separate networks, one audio call and one video call, then test reject, hangup, permission denial, app backgrounding, and reconnect.
