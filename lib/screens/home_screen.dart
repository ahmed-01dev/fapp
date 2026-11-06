import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/wasel_service.dart';
import '../widgets/glass_ui.dart';
import 'auth_screen.dart';
import 'chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final WaselService service;
  int tab = 0;
  List<Map<String, dynamic>> conversations = [];
  List<Map<String, dynamic>> nearby = [];
  Map<String, dynamic>? profile;
  bool nearbyEnabled = false;
  bool loading = true;
  String? error;
  Timer? nearbyTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    service = WaselService(Supabase.instance.client);
    _load();
  }

  @override
  void dispose() {
    nearbyTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      nearbyTimer?.cancel();
      if (nearbyEnabled) {
        service.disableNearby();
        if (mounted) setState(() { nearbyEnabled = false; nearby = []; });
      }
    }
  }

  Future<void> _load() async {
    try {
      final chats = await service.loadConversations();
      final me = await service.myProfile();
      if (!mounted) return;
      setState(() {
        conversations = chats;
        profile = me;
        loading = false;
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() { error = e.toString(); loading = false; });
    }
  }

  Future<void> _toggleNearby(bool enabled) async {
    if (!enabled) {
      nearbyTimer?.cancel();
      try { await service.disableNearby(); } catch (_) {}
      if (mounted) setState(() { nearbyEnabled = false; nearby = []; });
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (mounted) _message('لم يتم منح إذن الموقع. يمكنك تفعيله لاحقاً من إعدادات الهاتف.');
      return;
    }
    try {
      final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.low));
      await service.enableNearby(position.latitude, position.longitude);
      final matches = await service.nearbyMatches();
      if (mounted) setState(() { nearbyEnabled = true; nearby = matches; });
      nearbyTimer?.cancel();
      nearbyTimer = Timer.periodic(const Duration(minutes: 10), (_) => _refreshNearby());
    } catch (_) { if (mounted) _message('تعذر تفعيل القريبين. تأكد من إعداد قاعدة البيانات.'); }
  }

  Future<void> _refreshNearby() async {
    if (!nearbyEnabled) return;
    try {
      final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.low));
      await service.enableNearby(position.latitude, position.longitude);
      final matches = await service.nearbyMatches();
      if (mounted && nearbyEnabled) setState(() => nearby = matches);
    } catch (_) {}
  }

  void _message(String value) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));

  Future<void> _setUsername() async {
    final controller = TextEditingController(text: profile?['username']?.toString() ?? '');
    final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF191824),
      title: const Text('اسم المستخدم'),
      content: TextField(controller: controller, textDirection: TextDirection.ltr, decoration: const InputDecoration(prefixText: '@', hintText: 'yourname')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('حفظ')),
      ],
    ));
    controller.dispose();
    if (value == null) return;
    try { await service.saveUsername(value); await _load(); if (mounted) _message('تم تحديث اليوزرنيم'); }
    catch (e) { if (mounted) _message(e.toString()); }
  }

  Future<void> _newChat() async {
    final controller = TextEditingController();
    final username = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF191824),
      title: const Text('ابدأ تواصل جديد'),
      content: TextField(controller: controller, textDirection: TextDirection.ltr, decoration: const InputDecoration(prefixText: '@', hintText: 'username')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('بحث')),
      ],
    ));
    controller.dispose();
    if (username == null || username.trim().isEmpty) return;
    try {
      final users = await service.searchUsername(username);
      if (users.isEmpty) { _message('مش لاقيين اليوزر ده. راجع كتابته وجرب تاني.'); return; }
      final other = users.first;
      if (other['id'] == service.userId) { _message('ده حسابك أنت 😄'); return; }
      await service.sendContactRequest(other['id'] as String);
      if (mounted) _message('طلب التواصل اتبعت. المحادثة هتفتح بعد الموافقة.');
    } catch (e) { if (mounted) _message(e.toString()); }
  }

  Future<void> _showRequests() async {
    try {
      final requests = await service.loadIncomingRequests();
      if (!mounted) return;
      if (requests.isEmpty) { _message('مفيش طلبات تواصل جديدة.'); return; }
      await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF191824),
        title: const Text('طلبات التواصل'),
        content: SizedBox(width: 360, child: ListView.separated(
          shrinkWrap: true, itemCount: requests.length,
          separatorBuilder: (_, __) => const Divider(color: Colors.white12),
          itemBuilder: (context, index) {
            final request = requests[index];
            final sender = request['sender'] as Map<String, dynamic>?;
            final name = sender?['display_name']?.toString() ?? 'مستخدم';
            final username = sender?['username']?.toString();
            return ListTile(
              leading: WaselAvatar(label: name),
              title: Text(name),
              subtitle: Text(username == null ? 'طلب محادثة' : '@$username'),
              trailing: FilledButton(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(dialogContext);
                  try {
                    await service.acceptContactRequest(request['id'] as String);
                    await _load();
                    if (mounted) messenger.showSnackBar(const SnackBar(content: Text('تم قبول الطلب وفتح المحادثة.')));
                  } catch (e) { if (mounted) messenger.showSnackBar(SnackBar(content: Text(e.toString()))); }
                },
                child: const Text('قبول'),
              ),
            );
          },
        )),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إغلاق'))],
      ));
    } catch (e) { if (mounted) _message(e.toString()); }
  }

  Future<void> _openChat(Map<String, dynamic> item) async {
    final person = item['other_user'] as Map<String, dynamic>?;
    final title = person?['display_name']?.toString() ?? 'محادثة';
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(
      service: service, conversationId: item['id'] as String, title: title,
    )));
    _load();
  }

  Future<void> _signOut() async {
    await service.disableNearby();
    await Supabase.instance.client.auth.signOut();
    if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AuthScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: waselBg,
      body: GlassBackground(child: SafeArea(child: loading
        ? const Center(child: CircularProgressIndicator(color: waselPurple))
        : error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(error!, textAlign: TextAlign.center)))
          : IndexedStack(index: tab, children: [_chats(), _nearby(), _profile()]))),
      floatingActionButton: tab == 0 ? FloatingActionButton(
        onPressed: _newChat,
        backgroundColor: waselPurple,
        foregroundColor: Colors.white,
        elevation: 12,
        child: const Icon(Icons.edit_rounded),
      ) : null,
      bottomNavigationBar: SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: GlassPanel(radius: 26, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), opacity: .95,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _navItem(0, Icons.chat_bubble_rounded, 'الدردشات'),
            _navItem(1, Icons.radar_rounded, 'القريبون'),
            _navItem(2, Icons.person_rounded, 'حسابي'),
          ]),
        ),
      )),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final selected = tab == index;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => tab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? waselPurple.withOpacity(.20) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: selected ? Border.all(color: waselPurple.withOpacity(.28)) : null,
        ),
        child: Row(children: [
          Icon(icon, color: selected ? waselCyan : const Color(0xFF88869A), size: 20),
          if (selected) ...[const SizedBox(width: 8), Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))],
        ]),
      ),
    );
  }

  Widget _chats() => RefreshIndicator(
    onRefresh: _load,
    color: waselPurple,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
      children: [
        Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(gradient: const LinearGradient(colors: [waselPurple, waselCyan]), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.forum_rounded, color: Colors.white)),
          const SizedBox(width: 12),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('WASEL', style: TextStyle(fontSize: 12, letterSpacing: 3, color: waselCyan, fontWeight: FontWeight.w800)),
            Text('مساحتك. ناسك. كلامك.', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ])),
          IconButton(onPressed: _showRequests, icon: const Icon(Icons.mark_email_unread_outlined, color: Colors.white70)),
          IconButton(onPressed: _newChat, icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white70)),
        ]),
        const SizedBox(height: 26),
        const Text('أهلاً بيك 👋', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
        const SizedBox(height: 5),
        const Text('كل محادثاتك، في مكان واحد.', style: TextStyle(color: Color(0xFF9996AA))),
        const SizedBox(height: 22),
        GlassPanel(padding: const EdgeInsets.all(18), radius: 24, opacity: .8, child: Row(children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(color: waselPurple.withOpacity(.18), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.bolt_rounded, color: waselPurple, size: 27)),
          const SizedBox(width: 13),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ابدأ محادثة جديدة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            SizedBox(height: 4),
            Text('ابحث باليوزرنيم وتواصل بأمان', style: TextStyle(color: Color(0xFF9996AA), fontSize: 12)),
          ])),
          IconButton(onPressed: _newChat, icon: const Icon(Icons.arrow_forward_rounded, color: waselCyan)),
        ])),
        const SizedBox(height: 25),
        Row(children: [
          const Expanded(child: Text('رسائلك', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
          Text('${conversations.length} محادثة', style: const TextStyle(color: Color(0xFF89869A), fontSize: 12)),
        ]),
        const SizedBox(height: 12),
        if (conversations.isEmpty) GlassPanel(padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20), child: Column(children: [
          const Icon(Icons.forum_outlined, color: waselPurple, size: 42),
          const SizedBox(height: 12),
          const Text('لسه مفيش رسائل', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 5),
          const Text('أول محادثة ليك مستنياك هنا.', style: TextStyle(color: Color(0xFF9996AA))),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _newChat, icon: const Icon(Icons.add), label: const Text('ابدأ دلوقتي')),
        ])),
        ...conversations.map((item) {
          final person = item['other_user'] as Map<String, dynamic>?;
          final name = person?['display_name']?.toString() ?? 'محادثة';
          final username = person?['username']?.toString();
          return Padding(padding: const EdgeInsets.only(bottom: 10), child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => _openChat(item),
              child: GlassPanel(padding: const EdgeInsets.all(13), radius: 22, child: Row(children: [
                WaselAvatar(label: name, online: false, size: 52),
                const SizedBox(width: 13),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 5),
                  Text(username == null ? 'محادثة خاصة' : '@$username', style: const TextStyle(color: Color(0xFF9996AA), fontSize: 12)),
                ])),
                const Icon(Icons.chevron_left_rounded, color: Color(0xFF777487)),
              ])),
            ),
          ));
        }),
      ],
    ),
  );

  Widget _nearby() => ListView(padding: const EdgeInsets.fromLTRB(20, 22, 20, 120), children: [
    const Text('اكتشف القريبين', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
    const SizedBox(height: 7),
    const Text('تواصل مع ناس اختاروا الظهور بالقرب منك.', style: TextStyle(color: Color(0xFF9996AA))),
    const SizedBox(height: 22),
    GlassPanel(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 58, height: 58, decoration: BoxDecoration(gradient: const LinearGradient(colors: [waselPurple, waselCyan]), borderRadius: BorderRadius.circular(19)), child: const Icon(Icons.radar_rounded, color: Colors.white, size: 31)),
      const SizedBox(height: 17),
      const Text('Nearby', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      const SizedBox(height: 7),
      const Text('اختيارك بإيدك بالكامل. موقعك لا يظهر على الخريطة ولا نعرض إحداثيات دقيقة أو رقم هاتفك.', style: TextStyle(color: Color(0xFFAAA7BA), height: 1.6)),
      const SizedBox(height: 14),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        activeThumbColor: waselCyan,
        title: const Text('فعّل الظهور للقريبين', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(nearbyEnabled ? 'أنت ظاهر حالياً ويمكنك الإيقاف فوراً.' : 'متوقف افتراضياً'),
        value: nearbyEnabled,
        onChanged: _toggleNearby,
      ),
      const Text('تُحدّث البيانات أثناء فتح التطبيق، وتنتهي صلاحيتها تلقائياً بعد 30 دقيقة.', style: TextStyle(color: Color(0xFF777487), fontSize: 11)),
    ])),
    const SizedBox(height: 24),
    Row(children: [
      const Expanded(child: Text('ناس بالقرب منك', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19))),
      Text(nearbyEnabled ? '${nearby.length}' : 'مخفي', style: const TextStyle(color: waselCyan)),
    ]),
    const SizedBox(height: 12),
    if (!nearbyEnabled) const Text('فعّل الميزة عشان تشوف الأشخاص اللي اختاروا الظهور.', style: TextStyle(color: Color(0xFF9996AA))),
    if (nearbyEnabled && nearby.isEmpty) const Text('مفيش أشخاص ظاهرين بالقرب منك حالياً.', style: TextStyle(color: Color(0xFF9996AA))),
    ...nearby.map((person) {
      final name = person['display_name']?.toString() ?? 'مستخدم';
      final username = person['username']?.toString();
      final band = switch (person['distance_band']?.toString()) {
        'within_500m' => 'في حدود 500 م',
        'within_1km' => 'في حدود 1 كم',
        'within_3km' => 'في حدود 3 كم',
        'within_5km' => 'في حدود 5 كم',
        _ => 'بالقرب منك',
      };
      return Padding(padding: const EdgeInsets.only(bottom: 9), child: GlassPanel(child: Row(children: [
        WaselAvatar(label: name, size: 46),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(username == null ? 'مستخدم واصل' : '@$username', style: const TextStyle(color: Color(0xFF9996AA), fontSize: 12)),
        ])),
        Text(band, style: const TextStyle(color: waselCyan, fontSize: 11, fontWeight: FontWeight.w700)),
      ])));
    }),
  ]);

  Widget _profile() {
    final name = profile?['display_name']?.toString() ?? 'مستخدم واصل';
    final username = profile?['username']?.toString();
    return ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 120), children: [
      const Text('حسابك', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
      const SizedBox(height: 20),
      GlassPanel(padding: const EdgeInsets.all(24), child: Column(children: [
        WaselAvatar(label: name, size: 82),
        const SizedBox(height: 14),
        Text(name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 21)),
        const SizedBox(height: 5),
        Text(username == null ? 'أضف يوزرنيم عشان أصحابك يلاقوك' : '@$username', style: const TextStyle(color: Color(0xFF9996AA))),
        const SizedBox(height: 17),
        OutlinedButton.icon(onPressed: _setUsername, icon: const Icon(Icons.alternate_email_rounded), label: const Text('تعديل اليوزرنيم')),
      ])),
      const SizedBox(height: 16),
      GlassPanel(padding: EdgeInsets.zero, child: Column(children: [
        ListTile(leading: const Icon(Icons.shield_outlined, color: waselCyan), title: const Text('الخصوصية والأمان'), subtitle: const Text('إعدادات رقم الهاتف قيد الاستكمال')),
        const Divider(color: Colors.white10, height: 1),
        ListTile(leading: const Icon(Icons.logout_rounded, color: Color(0xFFFF7B8A)), title: const Text('تسجيل الخروج'), onTap: _signOut),
      ])),
      const SizedBox(height: 20),
      const Center(child: Text('WASEL  •  YOUR SPACE TO CONNECT', style: TextStyle(color: Color(0xFF666477), fontSize: 10, letterSpacing: 1.2))),
    ]);
  }
}
