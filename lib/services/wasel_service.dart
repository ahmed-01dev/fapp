import 'dart:math';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

class WaselService {
  WaselService(this.client);
  final SupabaseClient client;
  String get userId => client.auth.currentUser!.id;

  Future<Map<String, dynamic>?> myProfile() async =>
      await client.from('profiles').select('id,username,display_name,phone_visibility').eq('id', userId).maybeSingle();

  Future<void> saveUsername(String username) async {
    final normalized = username.trim().replaceFirst(RegExp(r'^@'), '');
    if (!RegExp(r'^[a-zA-Z0-9_.]{3,24}$').hasMatch(normalized)) {
      throw const FormatException('اسم المستخدم من 3 إلى 24 حرفاً: إنجليزي أو أرقام أو _ أو .');
    }
    await client.from('profiles').update({'username': normalized}).eq('id', userId);
  }

  Future<List<Map<String, dynamic>>> searchUsername(String username) async {
    final result = await client.rpc('search_profiles_by_username', params: {'p_query': username});
    return List<Map<String, dynamic>>.from(result as List);
  }

  Future<void> sendContactRequest(String otherUserId) async {
    await client.from('contact_requests').insert({
      'sender_id': userId,
      'recipient_id': otherUserId,
      'status': 'pending',
    });
  }

  Future<List<Map<String, dynamic>>> loadIncomingRequests() async {
    final requests = await client.from('contact_requests')
        .select('id,sender_id,created_at')
        .eq('recipient_id', userId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    final result = <Map<String, dynamic>>[];
    for (final request in requests) {
      final people = await client.from('profiles')
          .select('id,username,display_name')
          .eq('id', request['sender_id'] as String);
      result.add({...request, 'sender': people.isEmpty ? null : people.first});
    }
    return result;
  }

  Future<void> acceptContactRequest(String requestId) async {
    await client.from('contact_requests').update({'status': 'accepted'})
        .eq('id', requestId).eq('recipient_id', userId).eq('status', 'pending');
  }

  Future<String?> otherParticipantId(String conversationId) async {
    final members = await client
        .from('conversation_members')
        .select('user_id')
        .eq('conversation_id', conversationId);
    for (final member in members) {
      final id = member['user_id'] as String;
      if (id != userId) return id;
    }
    return null;
  }

  Future<void> blockUser(String otherUserId) async {
    if (otherUserId == userId) {
      throw const FormatException('لا يمكنك حظر حسابك.');
    }
    await client.from('user_blocks').upsert({
      'blocker_id': userId,
      'blocked_id': otherUserId,
    }, onConflict: 'blocker_id,blocked_id');
  }

  Future<void> unblockUser(String otherUserId) async {
    await client.from('user_blocks')
        .delete()
        .eq('blocker_id', userId)
        .eq('blocked_id', otherUserId);
  }

  Future<void> reportUser({
    required String reportedUserId,
    required String reason,
    String? details,
  }) async {
    const allowed = {
      'spam', 'harassment', 'impersonation', 'scam', 'unsafe_content', 'other',
    };
    if (!allowed.contains(reason)) {
      throw const FormatException('سبب الإبلاغ غير صالح.');
    }
    final note = details?.trim();
    await client.from('user_reports').insert({
      'reporter_id': userId,
      'reported_user_id': reportedUserId,
      'reason': reason,
      if (note != null && note.isNotEmpty) 'details': note,
    });
  }

  Future<void> sendMessage(String conversationId, String body) async {
    final text = body.trim();
    if (text.isEmpty) return;
    final row = await client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': userId,
      'body': text,
      'message_type': 'text',
    }).select('id').single();
    try {
      await client.functions.invoke('push-dispatch', body: {'message_id': row['id']});
    } catch (_) {
      // Notification delivery is independent of the message transaction.
    }
  }

  Future<void> markMessagesRead(List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await client.from('message_receipts').upsert(
      messageIds.map((id) => {
        'message_id': id,
        'user_id': userId,
        'delivered_at': now,
        'read_at': now,
      }).toList(),
      onConflict: 'message_id,user_id',
    );
  }

  Future<List<Map<String, dynamic>>> loadConversations() async {
    final memberships = await client.from('conversation_members').select('conversation_id').eq('user_id', userId);
    final ids = memberships.map((e) => e['conversation_id'] as String).toList();
    if (ids.isEmpty) return [];
    final rows = await client.from('conversations').select('id,kind,title,username,created_at').inFilter('id', ids).order('created_at', ascending: false);
    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      final members = await client.from('conversation_members').select('user_id').eq('conversation_id', row['id'] as String);
      final otherIds = members.map((m) => m['user_id'] as String).where((id) => id != userId).toList();
      final people = otherIds.isEmpty ? <Map<String, dynamic>>[] :
        List<Map<String, dynamic>>.from(await client.from('profiles').select('id,username,display_name').inFilter('id', otherIds));
      result.add({...row, 'other_user': people.isEmpty ? null : people.first});
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> loadMessages(String conversationId) async {
    final rows = await client.from('messages').select('id,sender_id,body,created_at')
      .eq('conversation_id', conversationId).isFilter('deleted_at', null).order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> enableNearby(double latitude, double longitude) async {
    await client.rpc('nearby_enable', params: {'p_lat': latitude, 'p_lon': longitude});
  }

  Future<void> disableNearby() async {
    await client.rpc('nearby_disable');
  }

  Future<List<Map<String, dynamic>>> nearbyMatches() async {
    final rows = await client.rpc('nearby_matches');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<String> createGroup(String title, List<String> memberIds) async {
    final result = await client.rpc('create_group', params: {
      'p_title': title.trim(),
      'p_member_ids': memberIds,
    });
    return result as String;
  }

  Future<String> createChannel({
    required String title,
    String? username,
    String? description,
  }) async {
    final result = await client.rpc('create_channel', params: {
      'p_title': title.trim(),
      'p_username': username?.trim(),
      'p_description': description?.trim(),
    });
    return result as String;
  }

  Future<void> joinPublicChannel(String conversationId) async {
    await client.from('conversation_members').upsert({
      'conversation_id': conversationId,
      'user_id': userId,
    }, onConflict: 'conversation_id,user_id', ignoreDuplicates: true);
  }

  Future<void> leaveConversation(String conversationId) async {
    await client.from('conversation_members').delete()
        .eq('conversation_id', conversationId)
        .eq('user_id', userId);
  }

  Future<void> markMessageDelivered(String messageId) async {
    await client.from('message_receipts').upsert({
      'message_id': messageId,
      'user_id': userId,
      'delivered_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'message_id,user_id', ignoreDuplicates: true);
  }

  Future<void> markMessageRead(String messageId) async {
    await client.from('message_receipts').upsert({
      'message_id': messageId,
      'user_id': userId,
      'delivered_at': DateTime.now().toUtc().toIso8601String(),
      'read_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'message_id,user_id');
  }

  Future<void> toggleReaction(String messageId, String emoji, {required bool add}) async {
    if (add) {
      await client.from('message_reactions').upsert({
        'message_id': messageId,
        'user_id': userId,
        'emoji': emoji,
      }, onConflict: 'message_id,user_id,emoji', ignoreDuplicates: true);
    } else {
      await client.from('message_reactions').delete()
          .eq('message_id', messageId)
          .eq('user_id', userId)
          .eq('emoji', emoji);
    }
  }

  Future<void> pinMessage(String conversationId, String messageId) async {
    await client.from('pinned_messages').upsert({
      'conversation_id': conversationId,
      'message_id': messageId,
      'pinned_by': userId,
    }, onConflict: 'conversation_id,message_id', ignoreDuplicates: true);
  }

  Future<void> unpinMessage(String conversationId, String messageId) async {
    await client.from('pinned_messages').delete()
        .eq('conversation_id', conversationId)
        .eq('message_id', messageId);
  }

  Future<void> setTyping(String conversationId, {required bool typing}) async {
    if (typing) {
      await client.from('typing_presence').upsert({
        'conversation_id': conversationId,
        'user_id': userId,
        'expires_at': DateTime.now().toUtc().add(const Duration(seconds: 8)).toIso8601String(),
      }, onConflict: 'conversation_id,user_id');
    } else {
      await client.from('typing_presence').delete()
          .eq('conversation_id', conversationId)
          .eq('user_id', userId);
    }
  }

  Future<Map<String, dynamic>> uploadAndSendMedia({
    required String conversationId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required String messageType,
    String? caption,
  }) async {
    const allowedTypes = {'image', 'video', 'audio', 'file'};
    if (!allowedTypes.contains(messageType)) {
      throw const FormatException('نوع الملف غير مدعوم.');
    }
    if (bytes.isEmpty || bytes.lengthInBytes > 50 * 1024 * 1024) {
      throw const FormatException('حجم الملف يجب أن يكون بين 1 بايت و50 ميجابايت.');
    }
    final safeName = fileName
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final random = Random.secure();
    final suffix = List.generate(12, (_) => random.nextInt(16).toRadixString(16)).join();
    final path = '$conversationId/$userId/${DateTime.now().microsecondsSinceEpoch}_${suffix}_${safeName.isEmpty ? 'upload' : safeName}';
    await client.storage.from('chat-media').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: mimeType, upsert: false),
    );
    try {
      final row = await client.from('messages').insert({
        'conversation_id': conversationId,
        'sender_id': userId,
        'body': caption?.trim().isNotEmpty == true ? caption!.trim() : fileName,
        'message_type': messageType,
        'media_path': path,
        'media_mime': mimeType,
        'media_size': bytes.lengthInBytes,
      }).select('id,conversation_id,sender_id,body,message_type,media_path,media_mime,media_size,created_at').single();
      try {
        await client.functions.invoke('push-dispatch', body: {'message_id': row['id']});
      } catch (_) {}
      return Map<String, dynamic>.from(row);
    } catch (_) {
      await client.storage.from('chat-media').remove([path]);
      rethrow;
    }
  }

  Future<String> mediaSignedUrl(String path, {Duration expiresIn = const Duration(hours: 1)}) async {
    return client.storage.from('chat-media').createSignedUrl(
      path,
      expiresIn.inSeconds,
    );
  }

  Future<void> registerPushToken(String token, String platform) async {
    if (token.trim().length < 20 || !{'android', 'ios'}.contains(platform)) {
      throw const FormatException('بيانات جهاز الإشعارات غير صالحة.');
    }
    await client.from('device_push_tokens').upsert({
      'user_id': userId,
      'token': token.trim(),
      'platform': platform,
      'disabled_at': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'token');
  }

  Future<void> disablePushToken(String token) async {
    await client.from('device_push_tokens').delete()
        .eq('token', token)
        .eq('user_id', userId);
  }

  Future<String> startCall({
    required String conversationId,
    required String calleeId,
    String callType = 'audio',
  }) async {
    if (!{'audio', 'video'}.contains(callType) || calleeId == userId) {
      throw const FormatException('بيانات المكالمة غير صالحة.');
    }
    final row = await client.from('call_sessions').insert({
      'conversation_id': conversationId,
      'caller_id': userId,
      'callee_id': calleeId,
      'call_type': callType,
      'status': 'ringing',
    }).select('id').single();
    final callId = row['id'] as String;
    // Push is best-effort: a provider outage must not prevent an in-app call.
    try {
      await client.functions.invoke('call-dispatch', body: {'call_id': callId});
    } catch (_) {}
    return callId;
  }

  Future<List<Map<String, dynamic>>> getCallIceServers(String callId) async {
    const fallback = <Map<String, dynamic>>[
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ],
      },
    ];
    try {
      final response = await client.functions.invoke(
        'call-ice-config',
        body: {'call_id': callId},
      );
      final data = response.data;
      if (data is Map && data['iceServers'] is List) {
        final servers = (data['iceServers'] as List)
            .whereType<Map>()
            .map((server) => Map<String, dynamic>.from(server))
            .where((server) => server['urls'] != null)
            .toList();
        if (servers.isNotEmpty) return servers;
      }
    } catch (_) {
      // Keep the call path available with public STUN if TURN credentials are not configured.
    }
    return fallback;
  }

  Future<void> sendCallSignal({
    required String callId,
    required String signalType,
    required Map<String, dynamic> payload,
  }) async {
    if (!{'offer', 'answer', 'ice', 'hangup'}.contains(signalType)) {
      throw const FormatException('نوع إشارة المكالمة غير صالح.');
    }
    await client.from('call_signals').insert({
      'call_id': callId,
      'sender_id': userId,
      'signal_type': signalType,
      'payload': payload,
    });
  }

  Stream<List<Map<String, dynamic>>> watchCallSignals(String callId) {
    return client.from('call_signals')
        .stream(primaryKey: ['id'])
        .eq('call_id', callId)
        .order('created_at');
  }

  Stream<List<Map<String, dynamic>>> watchCallSession(String callId) {
    return client.from('call_sessions')
        .stream(primaryKey: ['id'])
        .eq('id', callId);
  }

  Future<void> updateCallStatus(String callId, String status) async {
    if (!{'accepted', 'rejected', 'missed', 'ended'}.contains(status)) {
      throw const FormatException('حالة المكالمة غير صالحة.');
    }
    await client.from('call_sessions').update({
      'status': status,
      if (status == 'accepted') 'answered_at': DateTime.now().toUtc().toIso8601String(),
      if ({'rejected', 'missed', 'ended'}.contains(status))
        'ended_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', callId);
  }

  Future<void> sendReply(String conversationId, String body, String replyToId) async {
    final text = body.trim();
    if (text.isEmpty) return;
    final row = await client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': userId,
      'body': text,
      'message_type': 'text',
      'reply_to': replyToId,
    }).select('id').single();
    try {
      await client.functions.invoke('push-dispatch', body: {'message_id': row['id']});
    } catch (_) {}
  }

  Future<void> editMessage(String messageId, String body) async {
    final text = body.trim();
    if (text.isEmpty || text.length > 10000) {
      throw const FormatException('الرسالة يجب أن تكون بين 1 و10000 حرف.');
    }
    await client.from('messages').update({'body': text})
        .eq('id', messageId).eq('sender_id', userId);
  }

  Future<void> deleteMessage(String messageId) async {
    await client.from('messages').update({
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', messageId).eq('sender_id', userId);
  }

  Future<List<Map<String, dynamic>>> searchMessages(String conversationId, String query) async {
    final text = query.trim();
    if (text.isEmpty) return [];
    final rows = await client.from('messages')
        .select('id,sender_id,body,message_type,created_at,edited_at')
        .eq('conversation_id', conversationId)
        .isFilter('deleted_at', null)
        .ilike('body', '%$text%')
        .order('created_at', ascending: false)
        .limit(100);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> addConversationMember(String conversationId, String memberId) async {
    await client.from('conversation_members').insert({
      'conversation_id': conversationId,
      'user_id': memberId,
    });
  }

  Future<void> removeConversationMember(String conversationId, String memberId) async {
    if (memberId == userId) {
      await leaveConversation(conversationId);
      return;
    }
    await client.from('conversation_members').delete()
        .eq('conversation_id', conversationId)
        .eq('user_id', memberId);
  }

  Future<void> transferConversationOwnership(String conversationId, String newOwnerId) async {
    await client.rpc('transfer_conversation_ownership', params: {
      'p_conversation_id': conversationId,
      'p_new_owner_id': newOwnerId,
    });
  }

  Future<List<Map<String, dynamic>>> searchPublicChannels(String query) async {
    final text = query.trim();
    if (text.isEmpty) return [];
    final rows = await client.from('conversations')
        .select('id,title,description,username,created_at')
        .eq('kind', 'channel')
        .eq('is_public', true)
        .ilike('title', '%$text%')
        .order('created_at', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> setMyPresence(bool online) async {
    await client.rpc('set_my_presence', params: {'p_online': online});
  }
}
