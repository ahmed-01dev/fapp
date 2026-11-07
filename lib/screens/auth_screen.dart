import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/glass_ui.dart';
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
      setState(() => _error = 'اكتب الرقم بالصيغة الدولية، مثال: +2010xxxxxxx');
      return;
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
      if (response.user != null) {
        try {
          await Supabase.instance.client.functions.invoke('account-bootstrap');
        } catch (_) {
          await Supabase.instance.client.from('profiles').upsert({
            'id': response.user!.id,
            'display_name': 'مستخدم جديد',
          }, onConflict: 'id', ignoreDuplicates: true);
        }
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
            const Text('واصل', textAlign: TextAlign.center, style: TextStyle(fontSize: 37, fontWeight: FontWeight.w900, letterSpacing: -.5)),
            const SizedBox(height: 7),
            const Text('قريبين حتى لو بينا مسافات.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFAAA7BA), fontSize: 14)),
            const SizedBox(height: 34),
            GlassPanel(padding: const EdgeInsets.all(22), radius: 28, opacity: .78, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(_sent ? 'تأكيد رقمك' : 'أهلاً بيك من جديد', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
              const SizedBox(height: 7),
              Text(_sent ? 'اكتب كود التحقق اللي وصلك في رسالة SMS.' : 'سجّل برقم هاتفك وابدأ تواصل مع أصحابك.', style: const TextStyle(color: Color(0xFF9996AA), height: 1.5)),
              const SizedBox(height: 22),
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
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Color(0xFFFF8794), fontSize: 12)),
              ],
              const SizedBox(height: 18),
              SizedBox(height: 54, child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: waselPurple, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17))),
                onPressed: _busy ? null : (_sent ? _verifyCode : _sendCode),
                child: _busy ? const SizedBox(width: 21, height: 21, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_sent ? 'تأكيد الكود' : 'إرسال كود التحقق', style: const TextStyle(fontWeight: FontWeight.w800)),
              )),
              if (_sent) Center(child: TextButton(onPressed: _busy ? null : () => setState(() { _sent = false; _otp.clear(); }), child: const Text('تغيير رقم الهاتف'))),
            ])),
            const SizedBox(height: 18),
            const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.lock_outline_rounded, color: waselCyan, size: 14),
              SizedBox(width: 6),
              Text('رقمك محمي ولا يظهر إلا حسب إعدادات الخصوصية', style: TextStyle(color: Color(0xFF777487), fontSize: 10)),
            ]),
          ],
        )),
      )))),
    );
  }
}
