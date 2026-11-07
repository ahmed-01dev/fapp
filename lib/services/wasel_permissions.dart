import 'package:permission_handler/permission_handler.dart';

/// Requests sensitive permissions only when the feature that needs them starts.
class WaselPermissions {
  const WaselPermissions._();

  static Future<bool> requestCallPermissions({required bool video}) async {
    final permissions = <Permission>[
      Permission.microphone,
      if (video) Permission.camera,
    ];
    final statuses = await permissions.request();
    return statuses.values.every((status) => status.isGranted);
  }

  static Future<bool> requestNotificationPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted || status.isLimited;
  }

  static Future<bool> canOpenSettings() async => openAppSettings();
}
