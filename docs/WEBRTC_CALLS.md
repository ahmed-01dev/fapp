# WASEL calls — integration notes

## What this client now implements
- Audio and video call UI using `flutter_webrtc`.
- Peer-to-peer offer/answer and ICE candidate exchange using the existing private `call_sessions` and `call_signals` tables.
- Microphone mute, camera toggle, camera switch, accept/reject, and hangup.
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

## Important current limitations
- Incoming call UI is shown while the relevant conversation screen is open. Background/terminated incoming-call delivery is not implemented yet; it requires push call notifications and Android call-notification/foreground-service integration (plus APNs/CallKit for iOS).
- Public STUN servers do not relay media. Some carrier, office, school, and symmetric-NAT networks require TURN. Until TURN is configured, a call may fail to connect on those networks.
- Supabase signaling is authenticated and RLS-restricted to call participants, but this implementation is not end-to-end encrypted media signaling beyond WebRTC's standard DTLS-SRTP transport.
- A successful static build is not proof of real device-to-device operation. Test with two accounts on two separate networks, one audio call and one video call, then test reject, hangup, permission denial, app backgrounding, and reconnect.
