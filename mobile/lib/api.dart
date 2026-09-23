import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Client for one SolRay instance. The base URL is NEVER baked in — it comes
/// from the onboarding screen (first run) or stored preferences.
class Api {
  Api(this.baseUrl, {this.token});

  final String baseUrl; // e.g. https://tim-a.mediahost.stream (no trailing slash)
  String? token; // JWT after login

  Uri _u(String path, {Map<String, String>? query}) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Map<String, String> get _auth => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  /// Public endpoint — used by onboarding to validate the address.
  Future<Map<String, dynamic>> settings() async {
    final res = await http.get(_u('/api/settings')).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw Exception('Poslužitelj nije SolRay (HTTP ${res.statusCode})');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> login(String username, String password) async {
    final res = await http
        .post(_u('/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}))
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw Exception(_detail(res.body) ?? 'Prijava nije uspjela (HTTP ${res.statusCode})');
    }
    token = (jsonDecode(res.body) as Map<String, dynamic>)['access_token'] as String?;
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) => _json('GET', path, query: query);
  Future<dynamic> post(String path, Object body) => _json('POST', path, body: body);
  Future<dynamic> patch(String path, Object body) => _json('PATCH', path, body: body);
  Future<dynamic> put(String path, Object body) => _json('PUT', path, body: body);
  Future<dynamic> delete(String path) => _json('DELETE', path);

  Future<dynamic> _json(String method, String path, {Object? body, Map<String, String>? query}) async {
    if (token == null) throw Exception('Niste prijavljeni');
    final req = http.Request(method, _u(path, query: query))
      ..headers.addAll(_auth)
      ..body = jsonEncode(body ?? {});
    final res = await http.Response.fromStream(await req.send()).timeout(const Duration(seconds: 15));
    if (res.statusCode == 401) throw AuthExpired();
    if (res.statusCode >= 400) throw Exception(_detail(res.body) ?? 'HTTP ${res.statusCode}');
    if (res.body.isEmpty) return null;
    return jsonDecode(res.body);
  }

  String? _detail(String body) {
    try {
      final d = jsonDecode(body);
      if (d is Map && d['detail'] is String) return d['detail'] as String;
    } catch (_) {
      // non-JSON body — fall through
    }
    return null;
  }

  // ---- binary / multipart -------------------------------------------------

  /// Upload a file into a project's folder. [bytes] come from file_picker.
  Future<Map<String, dynamic>> upload(int? projectId, String fileName, List<int> bytes,
      {String contentType = 'application/octet-stream'}) async {
    final req = http.MultipartRequest(
      'POST',
      _u(projectId != null ? '/api/projects/$projectId/files' : '/api/files'),
    )
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
    final streamed = await req.send().timeout(const Duration(seconds: 120));
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode == 401) throw AuthExpired();
    if (res.statusCode >= 400) throw Exception(_detail(res.body) ?? 'Prijenos nije uspio (HTTP ${res.statusCode})');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Authenticated bytes of a stored file (download / open / share).
  Future<List<int>> download(int fileId) async {
    final res = await http
        .get(_u('/api/files/$fileId/download'), headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 120));
    if (res.statusCode == 401) throw AuthExpired();
    if (res.statusCode >= 400) throw Exception('Preuzimanje nije uspjelo (HTTP ${res.statusCode})');
    return res.bodyBytes;
  }

  /// URL of a thumbnail for Image.network (auth via ?token= like the web app).
  String thumbUrl(int fileId) => '$baseUrl/api/files/$fileId/thumb?token=${Uri.encodeComponent(token ?? '')}';

  // ---- ntfy WebSocket ------------------------------------------------------

  /// ntfy WebSocket for this user's topic (level-2 in-app notifications).
  /// Returns null when the instance has no public ntfy configured or the user
  /// has no topic yet.
  WebSocketChannel? notificationSocket(String ntfyBase, String topic) {
    if (ntfyBase.isEmpty || topic.isEmpty) return null;
    final ws = ntfyBase.replaceFirst(RegExp('^http'), 'ws');
    return WebSocketChannel.connect(Uri.parse('$ws/$topic/ws'));
  }

  // ---- persistence -------------------------------------------------------

  static const _kUrl = 'solray_url';
  static const _kToken = 'solray_token';

  static Future<String?> storedUrl() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kUrl);
  }

  static Future<String?> storedToken() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kToken);
  }

  static Future<void> saveSession(String url, String token) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUrl, url);
    await p.setString(_kToken, token);
  }

  static Future<void> clearSession() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kToken);
  }

  static Future<void> forgetServer() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kUrl);
    await p.remove(_kToken);
  }
}

class AuthExpired implements Exception {
  @override
  String toString() => 'Sesija je istekla — prijavite se ponovno.';
}
