import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/wasel_service.dart';

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
  List<Map<String, dynamic>> messages = [];
  bool loading = true;
  String? error;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { input.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final rows = await widget.service.loadMessages(widget.conversationId);
      if (mounted) setState(() { messages = rows; loading = false; });
    } catch (e) { if (mounted) setState(() { error = e.toString(); loading = false; }); }
  }

  Future<void> _send() async {
    final text = input.text;
    if (text.trim().isEmpty) return;
    input.clear();
    try { await widget.service.sendMessage(widget.conversationId, text); await _load(); }
    catch (e) { if (mounted) setState(() => error = e.toString()); }
  }

  @override
  Widget build(BuildContext context) {
    final myId = Supabase.instance.client.auth.currentUser!.id;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(children: [
        Expanded(child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: Supabase.instance.client.from('messages').stream(primaryKey: ['id']).eq('conversation_id', widget.conversationId).order('created_at'),
          builder: (context, snapshot) {
            final rows = snapshot.hasData ? snapshot.data! : messages;
            if (loading && !snapshot.hasData) return const Center(child: CircularProgressIndicator());
            if (error != null) return Center(child: Text(error!));
            if (rows.isEmpty) return const Center(child: Text('ابدأ أول رسالة 👋'));
            return ListView.builder(padding: const EdgeInsets.all(14), itemCount: rows.length, itemBuilder: (context, index) {
              final message = rows[index];
              final mine = message['sender_id'] == myId;
              return Align(
                alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 300),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: mine ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(message['body']?.toString() ?? ''),
                ),
              );
            });
          },
        )),
        SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 12), child: Row(children: [
          Expanded(child: TextField(controller: input, minLines: 1, maxLines: 5, decoration: const InputDecoration(hintText: 'اكتب رسالة...'))),
          const SizedBox(width: 8),
          IconButton.filled(onPressed: _send, icon: const Icon(Icons.send_rounded)),
        ]))),
      ]),
    );
  }
}
