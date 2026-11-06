import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/wasel_service.dart';
import '../widgets/glass_ui.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.service, required this.conversationId, required this.title});
  final WaselService service;
  final String conversationId;
  final String title;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final input = TextEditingController();
  final focus = FocusNode();
  final scroll = ScrollController();
  List<Map<String, dynamic>> messages = [];
  bool loading = true;
  bool sending = false;
  String? error;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { input.dispose(); focus.dispose(); scroll.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final rows = await widget.service.loadMessages(widget.conversationId);
      if (mounted) setState(() { messages = rows; loading = false; });
    } catch (e) {
      if (mounted) setState(() { error = e.toString(); loading = false; });
    }
  }

  Future<void> _send() async {
    final body = input.text.trim();
    if (body.isEmpty || sending) return;
    input.clear();
    setState(() { sending = true; error = null; });
    try {
      await widget.service.sendMessage(widget.conversationId, body);
      await _load();
      if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent + 120, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
    } catch (e) {
      if (mounted) {
        input.text = body;
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = Supabase.instance.client.auth.currentUser!.id;
    return Scaffold(
      backgroundColor: waselBg,
      resizeToAvoidBottomInset: true,
      body: GlassBackground(child: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(10, 6, 16, 12), child: Row(children: [
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
          WaselAvatar(label: widget.title, online: true, size: 43),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const Text('محادثة خاصة', style: TextStyle(color: waselCyan, fontSize: 11)),
          ])),
          IconButton(onPressed: () {}, icon: const Icon(Icons.more_horiz_rounded, color: Colors.white70)),
        ])),
        Expanded(child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: Supabase.instance.client.from('messages').stream(primaryKey: ['id']).eq('conversation_id', widget.conversationId).order('created_at'),
          builder: (context, snapshot) {
            final rows = snapshot.hasData ? snapshot.data! : messages;
            if (loading && !snapshot.hasData) return const Center(child: CircularProgressIndicator(color: waselPurple));
            if (error != null && rows.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(error!, textAlign: TextAlign.center)));
            if (rows.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 74, height: 74, decoration: BoxDecoration(color: waselPurple.withValues(alpha: .14), shape: BoxShape.circle), child: const Icon(Icons.waving_hand_rounded, color: waselPurple, size: 34)),
              const SizedBox(height: 15),
              const Text('أول رسالة تبدأ الحكاية', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 5),
              const Text('ابعت رسالة وابدأ الكلام.', style: TextStyle(color: Color(0xFF9996AA))),
            ]));
            return ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final message = rows[index];
                final mine = message['sender_id'] == myId;
                return Align(
                  alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                  child: Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: mine ? const LinearGradient(colors: [Color(0xFF7058C9), Color(0xFF493A83)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                      color: mine ? null : Colors.white.withValues(alpha: .075),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(20), topRight: const Radius.circular(20),
                        bottomLeft: Radius.circular(mine ? 20 : 5), bottomRight: Radius.circular(mine ? 5 : 20),
                      ),
                      border: Border.all(color: Colors.white.withValues(alpha: mine ? .16 : .10)),
                      boxShadow: mine ? [BoxShadow(color: waselPurple.withValues(alpha: .14), blurRadius: 18, offset: const Offset(0, 5))] : null,
                    ),
                    child: Text(message['body']?.toString() ?? '', style: const TextStyle(color: Colors.white, height: 1.45, fontSize: 14)),
                  ),
                );
              },
            );
          },
        )),
        if (error != null && messages.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(error!, style: const TextStyle(color: Color(0xFFFF8794), fontSize: 11))),
        Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 10), child: GlassPanel(radius: 25, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7), opacity: .95, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.add_circle_outline_rounded, color: waselCyan)),
          Expanded(child: TextField(
            controller: input, focusNode: focus, minLines: 1, maxLines: 5,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(hintText: 'اكتب رسالتك هنا...', filled: false, border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 5)),
          )),
          const SizedBox(width: 5),
          AnimatedContainer(duration: const Duration(milliseconds: 180), decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [waselPurple, Color(0xFF6C9BFF)])), child: IconButton(onPressed: sending ? null : _send, color: Colors.white, icon: sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.arrow_upward_rounded))),
        ]))),
      ]))),
    );
  }
}
