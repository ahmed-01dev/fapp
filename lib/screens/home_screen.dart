import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/wasel_service.dart';
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
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); service = WaselService(Supabase.instance.client); _load(); }

  @override
  void dispose() { nearbyTimer?.cancel(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      nearbyTimer?.cancel();
      if (nearbyEnabled) { service.disableNearby(); if (mounted) setState(() { nearbyEnabled = false; nearby = []; }); }
    }
  }

  Future<void> _refreshNearby() async {
    if (!nearbyEnabled) { return; }
    try {
      final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.low));
      await service.enableNearby(position.latitude, position.longitude);
      final matches = await service.nearbyMatches();
      if (mounted && nearbyEnabled) setState(() => nearby = matches);
    } catch (_) { /* Expiring server-side presence remains the privacy fallback. */ }
  }

  Future<void> _load() async {
    try {
      final chats = await service.loadConversations();
      final me = await service.myProfile();
      if (mounted) setState(() { conversations = chats; profile = me; loading = false; error = null; });
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
      if (mounted) setState(() => error = 'اسمح بالموقع أثناء استخدام الميزة فقط لتفعيل الأشخاص القريبين.');
      return;
    }
    try {
      final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.low));
      await service.enableNearby(position.latitude, position.longitude);
      final matches = await service.nearbyMatches();
      if (mounted) setState(() { nearbyEnabled = true; nearby = matches; error = null; });
      nearbyTimer?.cancel();
      nearbyTimer = Timer.periodic(const Duration(minutes: 10), (_) => _refreshNearby());
    } catch (_) {
      if (mounted) setState(() => error = 'تعذر تفعيل الأشخاص القريبين. تأكد من إعداد قاعدة البيانات.');
    }
  }

  Future<void> _setUsername() async {
    final controller = TextEditingController(text: profile?['username']?.toString() ?? '');
    final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('اسم المستخدم'),
      content: TextField(controller: controller, textDirection: TextDirection.ltr, decoration: const InputDecoration(prefixText: '@', hintText: 'yourname')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('حفظ')),
      ],
    ));
    controller.dispose();
    if (value == null) { return; }
    try { await service.saveUsername(value); await _load(); }
    catch (e) { if (mounted) setState(() => error = e.toString()); }
  }

  Future<void> _newChat() async {
    final controller = TextEditingController();
    final username = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('محادثة جديدة'),
      content: TextField(controller: controller, textDirection: TextDirection.ltr, decoration: const InputDecoration(prefixText: '@', hintText: 'username')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('بحث')),
      ],
    ));
    controller.dispose();
    if (username == null || username.trim().isEmpty) { return; }
    try {
      final users = await service.searchUsername(username);
      if (users.isEmpty) throw Exception('لم يتم العثور على اسم المستخدم.');
      final other = users.first;
      if (other['id'] == service.userId) throw Exception('ده حسابك أنت.');
      await service.sendContactRequest(other['id'] as String);
      if (!mounted) { return; }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال طلب التواصل. ستبدأ المحادثة بعد موافقة الطرف الآخر.')));
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
  }


  Future<void> _showRequests() async {
    try {
      final requests = await service.loadIncomingRequests();
      if (!mounted) return;
      if (requests.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد طلبات تواصل جديدة.')));
        return;
      }
      await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
        title: const Text('طلبات التواصل'),
        content: SizedBox(width: 360, child: ListView.separated(
          shrinkWrap: true,
          itemCount: requests.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, index) {
            final request = requests[index];
            final sender = request['sender'] as Map<String, dynamic>?;
            final displayName = sender?['display_name']?.toString() ?? 'مستخدم';
            final username = sender?['username']?.toString();
            return ListTile(
              title: Text(displayName),
              subtitle: Text(username == null ? 'طلب محادثة' : '@\${username}'),
              trailing: FilledButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  try {
                    await service.acceptContactRequest(request['id'] as String);
                    await _load();
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم قبول الطلب وفتح المحادثة.')));
                  } catch (e) {
                    if (mounted) setState(() => error = e.toString());
                  }
                },
                child: const Text('قبول'),
              ),
            );
          },
        )),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إغلاق'))],
      ));
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _signOut() async {
    await service.disableNearby();
    await Supabase.instance.client.auth.signOut();
    if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AuthScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_chats(), _nearby(), _profile()];
    return Scaffold(
      appBar: AppBar(title: const Text('واصل', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
        if (tab == 0) IconButton(onPressed: _showRequests, tooltip: 'طلبات التواصل', icon: const Icon(Icons.mark_email_unread_outlined)),
        if (tab == 0) IconButton(onPressed: _newChat, tooltip: 'محادثة جديدة', icon: const Icon(Icons.edit_outlined)),
      ]),
      body: loading ? const Center(child: CircularProgressIndicator()) :
        error != null ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(error!, textAlign: TextAlign.center))) : pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() { tab = value; error = null; }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'المحادثات'),
          NavigationDestination(icon: Icon(Icons.radar_rounded), label: 'القريبون'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'حسابي'),
        ],
      ),
    );
  }

  Widget _chats() {
    if (conversations.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.forum_outlined, size: 64), const SizedBox(height: 16),
      const Text('لسه مفيش محادثات', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8), const Text('ابدأ محادثة جديدة باستخدام اليوزرنيم.'),
      const SizedBox(height: 18), FilledButton.icon(onPressed: _newChat, icon: const Icon(Icons.add), label: const Text('محادثة جديدة')),
    ])));
    return RefreshIndicator(onRefresh: _load, child: ListView.separated(
      padding: const EdgeInsets.all(16), itemCount: conversations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = conversations[index];
        final person = item['other_user'] as Map<String, dynamic>?;
        final name = person?['display_name']?.toString() ?? 'محادثة';
        final username = person?['username']?.toString();
        return Card(child: ListTile(
          leading: CircleAvatar(child: Text(name.isEmpty ? 'و' : name.substring(0, 1))),
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(username == null ? 'محادثة خاصة' : '@' + username),
          trailing: const Icon(Icons.chevron_left_rounded),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(service: service, conversationId: item['id'] as String, title: name))),
        ));
      },
    ));
  }

  Widget _nearby() => ListView(padding: const EdgeInsets.all(20), children: [
    Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [Icon(Icons.radar_rounded), SizedBox(width: 10), Text('الأشخاص القريبون', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold))]),
      const SizedBox(height: 10),
      const Text('الميزة متوقفة افتراضياً. عند تفعيلها، سيظهر اسمك ويوزرك فقط مع مسافة تقريبية. لن تظهر إحداثياتك أو رقمك.'),
      const SizedBox(height: 12),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('السماح بالظهور بالقرب مني'), value: nearbyEnabled, onChanged: _toggleNearby),
      const Text('يمكنك إيقاف الظهور في أي وقت. تنتهي بيانات الموقع تلقائياً خلال 30 دقيقة من آخر تحديث.'),
    ]))),
    const SizedBox(height: 16),
    if (nearbyEnabled) ...[
      Text('أشخاص حولك (\${nearby.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      const SizedBox(height: 8),
      if (nearby.isEmpty) const Text('لا يوجد أشخاص ظاهرون بالقرب منك حالياً.'),
      ...nearby.map((person) => Card(child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
        title: Text(person['display_name']?.toString() ?? 'مستخدم'),
        subtitle: Text(person['username'] == null ? '' : '@\${person['username']}'),
        trailing: Text(_distanceLabel(person['distance_band']?.toString())),
      ))),
    ],
  ]);

  String _distanceLabel(String? band) => switch (band) {
    'within_500m' => 'في حدود 500 م',
    'within_1km' => 'في حدود 1 كم',
    'within_3km' => 'في حدود 3 كم',
    'within_5km' => 'في حدود 5 كم',
    _ => 'بالقرب منك',
  };

  Widget _profile() => ListView(padding: const EdgeInsets.all(20), children: [
    Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
      const CircleAvatar(radius: 36, child: Icon(Icons.person, size: 36)),
      const SizedBox(height: 12),
      Text(profile?['display_name']?.toString() ?? 'مستخدم واصل', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
      Text(profile?['username'] == null ? 'لم تضف يوزرنيم بعد' : '@\${profile!['username']}'),
      const SizedBox(height: 16),
      OutlinedButton.icon(onPressed: _setUsername, icon: const Icon(Icons.alternate_email), label: const Text('تعديل اليوزرنيم')),
    ]))),
    const SizedBox(height: 12),
    const ListTile(leading: Icon(Icons.privacy_tip_outlined), title: Text('الخصوصية'), subtitle: Text('إعدادات ظهور رقم الهاتف قيد الاستكمال')),
    ListTile(leading: const Icon(Icons.logout), title: const Text('تسجيل الخروج'), onTap: _signOut),
  ]);
}
