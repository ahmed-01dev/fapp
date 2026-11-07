import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
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
  final Map<String, Future<String>> mediaUrlCache = {};

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { input.dispose(); focus.dispose(); scroll.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final rows = await widget.service.loadMessages(widget.conversationId);
      final incomingIds = rows
          .where((row) => row['sender_id'] != widget.service.userId)
          .map((row) => row['id'] as String)
          .toList();
      if (incomingIds.isNotEmpty) {
        try { await widget.service.markMessagesRead(incomingIds); } catch (_) {}
      }
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

  Future<void> _pickAndSendMedia() async {
    if (sending) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        _showMessage('تعذر قراءة الملف من الهاتف. جرّب ملفاً آخر.');
        return;
      }
      final extension = (file.extension ?? '').toLowerCase();
      const mimeTypes = <String, String>{
        'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
        'webp': 'image/webp', 'gif': 'image/gif',
        'mp4': 'video/mp4', 'webm': 'video/webm',
        'mp3': 'audio/mpeg', 'aac': 'audio/aac', 'ogg': 'audio/ogg',
        'm4a': 'audio/mp4', 'wav': 'audio/wav',
        'pdf': 'application/pdf', 'txt': 'text/plain', 'csv': 'text/csv',
        'zip': 'application/zip', 'doc': 'application/msword',
        'xls': 'application/vnd.ms-excel', 'ppt': 'application/vnd.ms-powerpoint',
        'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      };
      final mime = mimeTypes[extension];
      if (mime == null) {
        _showMessage('نوع الملف غير مدعوم حالياً.');
        return;
      }
      final type = mime.startsWith('image/') ? 'image'
          : mime.startsWith('video/') ? 'video'
          : mime.startsWith('audio/') ? 'audio' : 'file';
      setState(() { sending = true; error = null; });
      await widget.service.uploadAndSendMedia(
        conversationId: widget.conversationId,
        bytes: bytes,
        fileName: file.name,
        mimeType: mime,
        messageType: type,
      );
      await _load();
    } catch (e) {
      if (mounted) _showMessage('تعذر إرسال الملف: $e');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<String> _signedMediaUrl(String path) {
    return mediaUrlCache.putIfAbsent(path, () => widget.service.mediaSignedUrl(path));
  }

  Future<void> _openMedia(String path) async {
    try {
      final url = await _signedMediaUrl(path);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) _showMessage('تعذر فتح الملف: $e');
    }
  }

  Widget _messageContent(Map<String, dynamic> message) {
    final type = message['message_type']?.toString() ?? 'text';
    final path = message['media_path']?.toString();
    if (type == 'image' && path != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<String>(
            future: _signedMediaUrl(path),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox(
                  width: 210, height: 150,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              return ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  snapshot.data!,
                  width: 230,
                  height: 190,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(
                    width: 210, height: 100,
                    child: Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
              );
            },
          ),
          if ((message['body']?.toString() ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(message['body'].toString()),
            ),
        ],
      );
    }
    if (type != 'text' && path != null) {
      final icon = switch (type) {
        'video' => Icons.play_circle_outline_rounded,
        'audio' => Icons.audio_file_rounded,
        _ => Icons.insert_drive_file_outlined,
      };
      return InkWell(
        onTap: () => _openMedia(path),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: waselCyan, size: 26),
          const SizedBox(width: 9),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(message['body']?.toString() ?? 'ملف مرفق', maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              const Text('اضغط لفتح الملف', style: TextStyle(color: Colors.white60, fontSize: 10)),
            ]),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.download_rounded, size: 18, color: Colors.white70),
        ]),
      );
    }
    return Text(message['body']?.toString() ?? '', style: const TextStyle(color: Colors.white, height: 1.45, fontSize: 14));
  }

  Future<void> _safetyAction(String action) async {
    try {
      final otherId = await widget.service.otherParticipantId(widget.conversationId);
      if (!mounted) return;
      if (otherId == null) {
        if (mounted) _showMessage('تعذر تحديد صاحب المحادثة.');
        return;
      }
      if (action == 'block') {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: const Color(0xFF191824),
            title: const Text('حظر المستخدم؟'),
            content: const Text('لن يتمكن هذا الحساب من إرسال طلبات تواصل إليك أو الظهور لك ضمن القريبين.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('حظر'),
              ),
            ],
          ),
        );
        if (confirm != true) return;
        await widget.service.blockUser(otherId);
        if (!mounted) return;
        _showMessage('تم حظر المستخدم.');
        Navigator.pop(context);
        return;
      }

      const reasons = <String, String>{
        'spam': 'رسائل مزعجة أو سبام',
        'harassment': 'مضايقة أو إساءة',
        'impersonation': 'انتحال شخصية',
        'scam': 'احتيال أو نصب',
        'unsafe_content': 'محتوى غير آمن',
        'other': 'سبب آخر',
      };
      final reason = await showDialog<String>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          backgroundColor: const Color(0xFF191824),
          title: const Text('الإبلاغ عن المستخدم'),
          children: reasons.entries.map((entry) => SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, entry.key),
            child: Text(entry.value),
          )).toList(),
        ),
      );
      if (reason == null) return;
      await widget.service.reportUser(reportedUserId: otherId, reason: reason);
      if (mounted) _showMessage('تم إرسال البلاغ للمراجعة.');
    } catch (e) {
      if (mounted) _showMessage('تعذر تنفيذ الطلب: $e');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz_rounded, color: Colors.white70),
            color: const Color(0xFF242132),
            onSelected: _safetyAction,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'report',
                child: Row(children: [
                  Icon(Icons.flag_outlined, color: waselCyan, size: 19),
                  SizedBox(width: 10),
                  Text('إبلاغ عن المستخدم'),
                ]),
              ),
              PopupMenuItem(
                value: 'block',
                child: Row(children: [
                  Icon(Icons.block_rounded, color: Color(0xFFFF7B8A), size: 19),
                  SizedBox(width: 10),
                  Text('حظر المستخدم'),
                ]),
              ),
            ],
          ),
        ])),
        Expanded(child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: Supabase.instance.client.from('messages').stream(primaryKey: ['id']).eq('conversation_id', widget.conversationId).order('created_at'),
          builder: (context, snapshot) {
            final rows = snapshot.hasData ? snapshot.data! : messages;
            if (loading && !snapshot.hasData) return const Center(child: CircularProgressIndicator(color: waselPurple));
            if (error != null && rows.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(error!, textAlign: TextAlign.center)));
            if (rows.isEmpty) { return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 74, height: 74, decoration: BoxDecoration(color: waselPurple.withValues(alpha: .14), shape: BoxShape.circle), child: const Icon(Icons.waving_hand_rounded, color: waselPurple, size: 34)),
              const SizedBox(height: 15),
              const Text('أول رسالة تبدأ الحكاية', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 5),
              const Text('ابعت رسالة وابدأ الكلام.', style: TextStyle(color: Color(0xFF9996AA))),
            ])); }
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
                    child: _messageContent(Map<String, dynamic>.from(message)),
                  ),
                );
              },
            );
          },
        )),
        if (error != null && messages.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(error!, style: const TextStyle(color: Color(0xFFFF8794), fontSize: 11))),
        Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 10), child: GlassPanel(radius: 25, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7), opacity: .95, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          IconButton(onPressed: sending ? null : _pickAndSendMedia, icon: const Icon(Icons.add_circle_outline_rounded, color: waselCyan)),
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
