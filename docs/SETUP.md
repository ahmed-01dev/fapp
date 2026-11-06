# Setup checklist

## Supabase project
1. Create a Supabase project and copy its Project URL and publishable key.
2. Run database/schema.sql in SQL Editor after reviewing it.
3. In Authentication > Providers, enable Phone and configure a supported SMS provider. Set OTP expiry and rate limits; enable CAPTCHA/abuse protection for public testing.
4. In API settings, expose public schema to the Data API. Keep private schema unexposed. Ensure authenticated has only the grants declared in schema.sql.
5. Enable Realtime for public.messages if the publication statement did not apply.
6. Schedule cleanup for expired nearby rows: DELETE FROM public.nearby_presence WHERE expires_at <= now(); Run every 10 minutes. The client query already ignores expired rows.
7. Test with two separate phone accounts. Verify users cannot read messages for conversations they do not belong to.

## Flutter
Run flutter create --platforms=android,ios --org com.wasel.app . once after cloning if native folders are absent. Then run flutter pub get.

Build Android:
flutter build apk --release --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...

For local Android builds, add ACCESS_COARSE_LOCATION and ACCESS_FINE_LOCATION to AndroidManifest.xml before using Nearby. For iOS, add NSLocationWhenInUseUsageDescription to Runner/Info.plist. The CI workflow performs these setup steps on its ephemeral runner.

## Important current limitations
- SMS delivery is not active until an SMS provider is configured in the Supabase project; sending OTP may incur provider charges.
- The MVP currently allows starting a direct conversation by username lookup. Stranger request acceptance, blocking, and reporting are mandatory before opening public discovery.
- Nearby heartbeats are sent when the user enables the feature. A later production iteration must refresh while active and explicitly disable on lifecycle/background transitions; the current 30-minute TTL is a fail-safe, not continuous tracking.
- Phone visibility settings are stored but phone-number search and contact-based discovery are not exposed.
- E2EE is not implemented in this MVP. No claim of end-to-end encryption is made.
