import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'wasel_service.dart';

class WaselPushNotifications {
  StreamSubscription<String>? _tokenSubscription;
  String? _lastToken;

  Future<void> initialize(WaselService service) async {
    if (Firebase.apps.isEmpty) return;

    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => null,
    };
    if (platform == null) return;

    final messaging = FirebaseMessaging.instance;
    NotificationSettings permission;
    try {
      permission = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
    } catch (_) {
      return;
    }
    if (permission.authorizationStatus == AuthorizationStatus.denied) return;

    try {
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        _lastToken = token;
        await service.registerPushToken(token, platform);
      }
    } catch (_) {
      // The app remains usable if the provider is temporarily unavailable.
    }

    await _tokenSubscription?.cancel();
    _tokenSubscription = messaging.onTokenRefresh.listen((token) async {
      if (token.isEmpty) return;
      final previous = _lastToken;
      if (previous != null && previous != token) {
        try { await service.disablePushToken(previous); } catch (_) {}
      }
      _lastToken = token;
      try {
        await service.registerPushToken(token, platform);
      } catch (_) {}
    });
  }

  Future<void> disableCurrentToken(WaselService service) async {
    final token = _lastToken ?? await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    try {
      await service.disablePushToken(token);
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    _tokenSubscription = null;
  }
}
