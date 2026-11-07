import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'widgets/glass_ui.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
const firebaseMessagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
const firebaseIosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final configured = supabaseUrl.startsWith('https://') && supabaseKey.isNotEmpty && !supabaseKey.contains('REPLACE_ME');
  if (configured) await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  final firebaseConfigured = firebaseApiKey.isNotEmpty &&
      firebaseAppId.isNotEmpty &&
      firebaseMessagingSenderId.isNotEmpty &&
      firebaseProjectId.isNotEmpty;
  if (firebaseConfigured) {
    await Firebase.initializeApp(options: FirebaseOptions(
      apiKey: firebaseApiKey,
      appId: firebaseAppId,
      messagingSenderId: firebaseMessagingSenderId,
      projectId: firebaseProjectId,
      iosBundleId: firebaseIosBundleId.isEmpty ? null : firebaseIosBundleId,
    ));
  }
  runApp(WaselApp(configured: configured));
}

class WaselApp extends StatelessWidget {
  const WaselApp({super.key, required this.configured});
  final bool configured;

  @override
  Widget build(BuildContext context) {
    const accent = waselPurple;
    final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.dark).copyWith(
      surface: waselPanel, primary: accent, secondary: waselCyan, onSurface: const Color(0xFFF4F2FF),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'واصل',
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: scheme,
        scaffoldBackgroundColor: waselBg,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, foregroundColor: Colors.white, elevation: 0, centerTitle: false),
        textTheme: ThemeData.dark().textTheme.apply(bodyColor: const Color(0xFFF4F2FF), displayColor: Colors.white),
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: Colors.white.withValues(alpha: .055),
          hintStyle: const TextStyle(color: Color(0xFF858496)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: Colors.white.withValues(alpha: .10))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: Colors.white.withValues(alpha: .10))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: waselPurple)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 17, vertical: 16),
        ),
        snackBarTheme: SnackBarThemeData(backgroundColor: const Color(0xFF242235), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF10111A), indicatorColor: waselPurple.withValues(alpha: .22),
          labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ),
      home: !configured ? const SetupRequiredScreen() :
        Supabase.instance.client.auth.currentSession == null ? const AuthScreen() : const HomeScreen(),
    );
  }
}

class SetupRequiredScreen extends StatelessWidget {
  const SetupRequiredScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: GlassBackground(child: SafeArea(child: Center(child: Padding(
      padding: const EdgeInsets.all(28),
      child: GlassPanel(padding: const EdgeInsets.all(26), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 76, height: 76, decoration: BoxDecoration(gradient: const LinearGradient(colors: [waselPurple, waselCyan]), borderRadius: BorderRadius.circular(25)), child: const Icon(Icons.forum_rounded, size: 38, color: Colors.white)),
        const SizedBox(height: 20),
        const Text('واصل', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        const Text('اربط مشروع Supabase أولاً لتفعيل تسجيل الدخول والمراسلة.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFB5B2C6))),
        const SizedBox(height: 18),
        const SelectableText('SUPABASE_URL و SUPABASE_PUBLISHABLE_KEY', textAlign: TextAlign.center, style: TextStyle(color: waselCyan)),
        const SizedBox(height: 8),
        const Text('راجع README.md لخطوات الإعداد.', style: TextStyle(color: Color(0xFF858496))),
      ])),
    )))),
  );
}
