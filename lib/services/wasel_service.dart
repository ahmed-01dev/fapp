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
    await client.from('messages').insert({'conversation_id': conversationId, 'sender_id': userId, 'body': text});
  }

  Future<List<Map<String, dynamic>>> loadConversations() async {
    final memberships = await client.from('conversation_members').select('conversation_id').eq('user_id', userId);
    final ids = memberships.map((e) => e['conversation_id'] as String).toList();
    if (ids.isEmpty) return [];
    final rows = await client.from('conversations').select('id,created_at').inFilter('id', ids).order('created_at', ascending: false);
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
}
