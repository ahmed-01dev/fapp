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

  Future<String> startDirectChat(String otherUserId) async {
    final conversation = await client.from('conversations').insert({'created_by': userId, 'kind': 'direct'}).select('id').single();
    final id = conversation['id'] as String;
    await client.from('conversation_members').insert({'conversation_id': id, 'user_id': userId});
    await client.from('conversation_members').insert({'conversation_id': id, 'user_id': otherUserId});
    return id;
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

  Future<void> enableNearby(double latitude, double longitude) async =>
      client.rpc('nearby_enable', params: {'p_lat': latitude, 'p_lon': longitude});
  Future<void> disableNearby() async => client.rpc('nearby_disable');
  Future<List<Map<String, dynamic>>> nearbyMatches() async =>
      List<Map<String, dynamic>>.from(await client.rpc('nearby_matches') as List);
}
