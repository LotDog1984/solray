import 'package:flutter/material.dart';

import '../api.dart';
import '../services/push.dart';
import 'login_screen.dart';

/// Shared handling of a dead session (HTTP 401 anywhere in the app):
/// drop the stored token (keep the server URL so the user logs into the
/// same instance), remove this device's push registration (its token was
/// tied to the dead JWT) and replace the whole stack with the login screen.
///
/// 1.18.1: the boot error screen's "Pokušaj ponovno" button used to retry
/// with the same dead token — a 401 loop that could only be escaped by
/// clearing the app's cache. Every 401 path now lands on the login screen.
Future<void> forceLoginScreen(BuildContext context, Api api) async {
  PushNotifications.unregister(api); // best-effort; ignore result
  await Api.clearSession();
  if (!context.mounted) return;
  Navigator.of(context).pushReplacement(MaterialPageRoute(
    builder: (_) => LoginScreen(baseUrl: api.baseUrl),
  ));
}
