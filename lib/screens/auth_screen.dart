import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() { _phone.dispose(); _otp.dispose(); super.dispose(); }

  Future<void> _sendCode() async {
    final phone = _phone.text.trim();
    if (!phone.startsWith('+') || phone.length < 9) {
      setState(() => _error = 'اكتب الرقم بالصيغة الدولية، مثال: +2010xxxxxxx'); return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await Supabase.instance.client.auth.signInWithOtp(phone: phone);
      if (mounted) setState(() => _sent = true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر إرسال الكود. حاول مرة أخرى.');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _verifyCode() async {
    final phone = _phone.text.trim();
    final token = _otp.text.trim();
    if (token.length != 6) { setState(() => _error = 'اكتب كود التحقق المكوّن من 6 أرقام.'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      final response = await Supabase.instance.client.auth.verifyOTP(phone: phone, token: token, type: OtpType.sms);
      final user = response.user;
      if (user != null) {
        await Supabase.instance.client.from('profiles').upsert({
          'id': user.id, 'display_name': 'مستخدم جديد',
        }, onConflict: 'id', ignoreDuplicates: true);
      }
      if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'الكود غير صحيح أو انتهت صلاحيته.');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.forum_rounded, size: 68),
          const SizedBox(height: 18),
          Text('واصل', textAlign: TextAlign.center, style: theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(_sent ? 'أدخل كود التحقق المرسل برسالة SMS' : 'كل محادثاتك في مكان واحد', textAlign: TextAlign.center),
          const SizedBox(height: 32),
          TextField(controller: _phone, keyboardType: TextInputType.phone, enabled: !_sent && !_busy, textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'رقم الهاتف الدولي', hintText: '+2010xxxxxxx', prefixIcon: Icon(Icons.phone_rounded))),
          if (_sent) ...[
            const SizedBox(height: 14),
            TextField(controller: _otp, keyboardType: TextInputType.number, maxLength: 6, textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'كود SMS', prefixIcon: Icon(Icons.lock_outline_rounded))),
          ],
          if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: theme.colorScheme.error))],
          const SizedBox(height: 18),
          FilledButton(onPressed: _busy ? null : (_sent ? _verifyCode : _sendCode),
            child: Padding(padding: const EdgeInsets.all(13), child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_sent ? 'تأكيد الكود' : 'إرسال كود التحقق'))),
          if (_sent) TextButton(onPressed: _busy ? null : () => setState(() { _sent = false; _otp.clear(); }), child: const Text('تغيير رقم الهاتف')),
          const SizedBox(height: 16),
          Text('بالمتابعة، أنت توافق على شروط الاستخدام وسياسة الخصوصية.', textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ],
      )),
    ))));
  }
}
