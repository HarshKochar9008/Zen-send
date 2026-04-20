import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persisted work that must run once the device has connectivity again.
class PendingBackendJobs {
  PendingBackendJobs._();

  static const _fcmPendingUserIdKey = 'pending_fcm_token_sync_user_v1';
  static const _pushQueueKey = 'pending_transfer_fcm_invoke_v1';
  static const _maxPushJobs = 32;

  static Future<void> markFcmTokenSyncPending(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fcmPendingUserIdKey, userId);
  }

  static Future<void> clearFcmTokenSyncPending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_fcmPendingUserIdKey);
  }

  static Future<String?> peekPendingFcmUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_fcmPendingUserIdKey);
    if (v == null || v.isEmpty) return null;
    return v;
  }

  static Future<void> enqueueTransferPushNotification({
    required String transferId,
    required String senderId,
    required String receiverId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await _loadPushQueue(prefs);
    final deduped = existing
        .where((j) => j['transfer_id']?.toString() != transferId)
        .toList();
    deduped.add({
      'transfer_id': transferId,
      'sender_id': senderId,
      'receiver_id': receiverId,
    });
    final capped = deduped.length > _maxPushJobs
        ? deduped.sublist(deduped.length - _maxPushJobs)
        : deduped;
    await prefs.setString(_pushQueueKey, jsonEncode(capped));
  }

  static Future<List<Map<String, String>>> loadTransferPushQueue() async {
    final prefs = await SharedPreferences.getInstance();
    return _loadPushQueue(prefs);
  }

  static Future<void> saveTransferPushQueue(
    List<Map<String, String>> jobs,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (jobs.isEmpty) {
      await prefs.remove(_pushQueueKey);
      return;
    }
    final capped =
        jobs.length > _maxPushJobs ? jobs.sublist(jobs.length - _maxPushJobs) : jobs;
    await prefs.setString(_pushQueueKey, jsonEncode(capped));
  }

  static Future<List<Map<String, String>>> _loadPushQueue(
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString(_pushQueueKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <Map<String, String>>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final tid = item['transfer_id']?.toString() ?? '';
        final sid = item['sender_id']?.toString() ?? '';
        final rid = item['receiver_id']?.toString() ?? '';
        if (tid.isEmpty || sid.isEmpty || rid.isEmpty) continue;
        out.add({
          'transfer_id': tid,
          'sender_id': sid,
          'receiver_id': rid,
        });
      }
      return out;
    } catch (_) {
      return [];
    }
  }
}
