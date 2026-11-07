import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/glass_ui.dart';
import 'home_screen.dart';

enum _AuthMode { phone, email }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  _AuthMode _mode = _AuthMode.phone;
  bool _sent = false;
  bool _busy = false;
  bool _signUp = true;
  bool _obscurePassword = true;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _setMode(_AuthMode mode) {
    setState(() {
      _mode = mode;
      _error = null;
      _notice = null;
      _sent = false;
    });
  }

  Future<void> _sendCode() async {
    final phone = _phone.text.trim();
    if (!phone.startsWith('+') || phone.length < 9) {
      setState(() => _error = 'اكتب الرقم بالصيغة الدولية، مثال: +2010xxxxxxx');
      return;
    }
    setState(() { _busy = true; _error = null; _notice = null; });
    try {
      await Supabase.instance.client.auth.signInWithOtp(phone: phone);
      if (mounted) setState(() => _sent = true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر إرسال الكود. جرّب التسجيل بالبريد الإلكتروني.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    final phone = _phone.text.trim();
    final token = _otp.text.trim();
    if (token.length != 6) {
      setState(() => _error = 'اكتب كود التحقق المكوّن من 6 أرقام.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final response = await Supabase.instance.client.auth.verifyOTP(
        phone: phone, token: token, type: OtpType.sms,
      );
      if (response.user != null) await _bootstrapProfile(response.user!);
      if (mounted) _openHome();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'الكود غير صحيح أو انتهت صلاحيته.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _emailAuth() async {
    final email = _email.text.trim().toLowerCase();
    final password = _password.text;
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _error = 'اكتب بريدًا إلكترونيًا صحيحًا.');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'كلمة المرور لازم تكون 8 أحرف على الأقل.');
      return;
    }
    setState(() { _busy = true; _error = null; _notice = null; });
    try {
      final auth = Supabase.instance.client.auth;
      if (_signUp) {
        final response = await auth.signUp(email: email, password: password);
        if (response.session != null && response.user != null) {
          await _bootstrapProfile(response.user!);
          if (mounted) _openHome();
        } else if (mounted) {
          setState(() => _notice = 'أنشأنا الحساب. افتح بريدك واضغط رابط التأكيد، وبعدها ارجع وسجّل الدخول.');
        }
      } else {
        final response = await auth.signInWithPassword(email: email, password: password);
        if (response.user != null) {
          await _bootstrapProfile(response.user!);
          if (mounted) _openHome();
        }
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'حصل خطأ. راجع الاتصال وحاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _error = 'اكتب بريدك الإلكتروني أولاً.');
      return;
    }
    setState(() { _busy = true; _error = null; _notice = null; });
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (mounted) setState(() => _notice = 'لو البريد مسجل، هيوصلك رابط استعادة كلمة المرور.');
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر إرسال رابط الاستعادة الآن.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _bootstrapProfile(User user) async {
    try {
      await Supabase.instance.client.functions.invoke('account-bootstrap');
    } catch (_) {
      await Supabase.instance.client.from('profiles').upsert({
        'id': user.id,
        'display_name': user.email?.split('@').first ?? 'مستخدم جديد',
      }, onConflict: 'id', ignoreDuplicates: true);
    }
  }

  void _openHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: waselBg,
      body: GlassBackground(child: SafeArea(child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Center(child: Container(
              width: 92, height: 92,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [waselPurple, waselCyan], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [BoxShadow(color: waselPurple.withValues(alpha: .35), blurRadius: 32, spreadRadius: 1)],
              ),
              child: const Icon(Icons.forum_rounded, size: 46, color: Colors.white),
            )),
            const SizedBox(height: 22),
            const Text('واصل', textAlign: TextAlign.center, style: TextStyle(fontSize: 37, fontWeight: FontWeight.w900)),
            const SizedBox(height: 7),
            const Text('قريبين حتى لو بينا مسافات.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFAAA7BA), fontSize: 14)),
            const SizedBox(height: 30),
            GlassPanel(padding: const EdgeInsets.all(20), radius: 28, opacity: .78, child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('اختار طريقة الدخول', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 16),
                SegmentedButton<_AuthMode>(
                  segments: const [
                    ButtonSegment(value: _AuthMode.phone, label: Text('رقم الهاتف'), icon: Icon(Icons.phone_iphone_rounded)),
                    ButtonSegment(value: _AuthMode.email, label: Text('البريد الإلكتروني'), icon: Icon(Icons.email_outlined)),
                  ],
                  selected: {_mode},
                  onSelectionChanged: _busy ? null : (value) => _setMode(value.first),
                  showSelectedIcon: false,
                ),
                const SizedBox(height: 20),
                if (_mode == _AuthMode.phone) ..._buildPhoneFields(),
                if (_mode == _AuthMode.email) ..._buildEmailFields(),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Color(0xFFFF8794), fontSize: 12)),
                ],
                if (_notice != null) ...[
                  const SizedBox(height: 12),
                  Text(_notice!, style: const TextStyle(color: waselCyan, fontSize: 12, height: 1.5)),
                ],
              ],
            )),
            const SizedBox(height: 18),
            const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.lock_outline_rounded, color: waselCyan, size: 14),
              SizedBox(width: 6),
              Text('بياناتك محمية ولا نعرض كلمة المرور لأي شخص', style: TextStyle(color: Color(0xFF777487), fontSize: 10)),
            ]),
          ],
        )),
      )))),
    );
  }

  List<Widget> _buildPhoneFields() => [
    Text(_sent ? 'تأكيد رقمك' : 'الدخول برقم الهاتف', style: const TextStyle(color: Color(0xFFAAA7BA))),
    const SizedBox(height: 14),
    TextField(
      controller: _phone, keyboardType: TextInputType.phone,
      enabled: !_sent && !_busy, textDirection: TextDirection.ltr,
      decoration: const InputDecoration(labelText: 'رقم الهاتف الدولي', hintText: '+2010xxxxxxx', prefixIcon: Icon(Icons.phone_iphone_rounded)),
    ),
    if (_sent) ...[
      const SizedBox(height: 14),
      TextField(controller: _otp, keyboardType: TextInputType.number, maxLength: 6, textDirection: TextDirection.ltr,
        decoration: const InputDecoration(labelText: 'كود SMS', prefixIcon: Icon(Icons.lock_outline_rounded))),
    ],
    const SizedBox(height: 18),
    _primaryButton(_sent ? 'تأكيد الكود' : 'إرسال كود التحقق', _sent ? _verifyCode : _sendCode),
    if (_sent) Center(child: TextButton(onPressed: _busy ? null : () => setState(() { _sent = false; _otp.clear(); }), child: const Text('تغيير رقم الهاتف'))),
    const SizedBox(height: 8),
    const Text('لو رسالة SMS ما وصلتش، اختار البريد الإلكتروني من الأعلى.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF858496), fontSize: 11)),
  ];

  List<Widget> _buildEmailFields() => [
    Text(_signUp ? 'إنشاء حساب جديد بالبريد' : 'تسجيل الدخول بالبريد', style: const TextStyle(color: Color(0xFFAAA7BA))),
    const SizedBox(height: 14),
    TextField(
      controller: _email, keyboardType: TextInputType.emailAddress,
      textDirection: TextDirection.ltr, autocorrect: false,
      decoration: const InputDecoration(labelText: 'البريد الإلكتروني', hintText: 'name@example.com', prefixIcon: Icon(Icons.email_outlined)),
    ),
    const SizedBox(height: 14),
    TextField(
      controller: _password, obscureText: _obscurePassword,
      textDirection: TextDirection.ltr, autocorrect: false,
      decoration: InputDecoration(
        labelText: 'كلمة المرور', prefixIcon: const Icon(Icons.lock_outline_rounded),
        suffixIcon: IconButton(
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
        ),
      ),
    ),
    if (_signUp) const Padding(
      padding: EdgeInsets.only(top: 8),
      child: Text('استخدم 8 أحرف على الأقل. قد تحتاج لتأكيد بريدك قبل الدخول.', style: TextStyle(color: Color(0xFF858496), fontSize: 11)),
    ),
    const SizedBox(height: 18),
    _primaryButton(_signUp ? 'إنشاء الحساب' : 'تسجيل الدخول', _emailAuth),
    if (!_signUp) Align(
      alignment: Alignment.center,
      child: TextButton(onPressed: _busy ? null : _resetPassword, child: const Text('نسيت كلمة المرور؟')),
    ),
    Center(
      child: TextButton(
        onPressed: _busy ? null : () => setState(() { _signUp = !_signUp; _error = null; _notice = null; }),
        child: Text(_signUp ? 'عندي حساب بالفعل — تسجيل الدخول' : 'ليس لديك حساب؟ إنشاء حساب جديد'),
      ),
    ),
  ];

  Widget _primaryButton(String label, VoidCallback action) => SizedBox(
    height: 54,
    child: FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: waselPurple, foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
      ),
      onPressed: _busy ? null : action,
      child: _busy
          ? const SizedBox(width: 21, height: 21, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    ),
  );
}
