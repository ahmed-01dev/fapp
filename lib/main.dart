import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final configured = supabaseUrl.startsWith('https://') && supabaseKey.isNotEmpty && !supabaseKey.contains('REPLACE_ME');
  if (configured) await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  runApp(WaselApp(configured: configured));
}

class WaselApp extends StatelessWidget {
  const WaselApp({super.key, required this.configured});
  final bool configured;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF6759E8);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'واصل',
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: const Color(0xFFF0F1F7),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
      darkTheme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark)),
      themeMode: ThemeMode.system,
      home: !configured ? const SetupRequiredScreen() :
        Supabase.instance.client.auth.currentSession == null ? const AuthScreen() : const HomeScreen(),
    );
  }
}

class SetupRequiredScreen extends StatelessWidget {
  const SetupRequiredScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.forum_rounded, size: 64),
        const SizedBox(height: 20),
        Text('واصل', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Text('اربط مشروع Supabase أولاً لتفعيل تسجيل الدخول والمراسلة.', textAlign: TextAlign.center),
        const SizedBox(height: 12),
        const SelectableText('SUPABASE_URL و SUPABASE_PUBLISHABLE_KEY'),
        const Text('راجع README.md لخطوات الإعداد.'),
      ]),
    ))),
  );
}
