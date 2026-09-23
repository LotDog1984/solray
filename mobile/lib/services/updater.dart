import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// In-app updates: check GitHub Releases for a newer APK, download it with
/// progress, and hand it to Android's installer. The repo/owner are fixed
/// (this is the app's own distribution channel); the *server* address never
/// enters this flow.
class Updater {
  static const owner = 'LotDog1984';
  static const repo = 'solray';

  static String? _currentVersion;

  /// This app's version (e.g. "1.6.3"), read from the Android build config.
  static Future<String> currentVersion() async {
    if (_currentVersion != null) return _currentVersion!;
    final info = await PackageInfo.fromPlatform();
    _currentVersion = info.version;
    return _currentVersion!;
  }

  /// Info about the newest published release, or null when GitHub is
  /// unreachable / rate-limited / the repo has no releases.
  static Future<ReleaseInfo?> latestRelease() async {
    try {
      final res = await http
          .get(Uri.parse('https://api.github.com/repos/$owner/$repo/releases/latest'))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final d = jsonDecode(res.body) as Map<String, dynamic>;
      return ReleaseInfo.fromJson(d);
    } catch (_) {
      return null;
    }
  }

  /// true when [latest] is strictly newer than the installed version.
  static bool isNewer(String latest, String current) {
    List<int> parse(String v) => v
        .replaceAll(RegExp(r'^[vV]'), '')
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    final a = parse(latest), b = parse(current);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  /// Stream the release APK to a temp file, reporting 0..100 progress.
  /// Returns the downloaded file path.
  static Future<String> downloadApk(
    ReleaseInfo release, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${release.apkAssetName}');
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(release.apkUrl))
        ..followRedirects = true;
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw Exception('Preuzimanje nije uspjelo (HTTP ${res.statusCode})');
      }
      final total = res.contentLength ?? release.apkSize;
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in res.stream) {
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      if (total > 0 && received < total * 0.95) {
        throw Exception('Preuzimanje je prekinuto ($received od $total bajtova)');
      }
      return file.path;
    } catch (_) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Hand the APK to Android's package installer (system dialog appears).
  static Future<void> install(String apkPath) async {
    final res = await OpenFilex.open(apkPath, type: 'application/vnd.android.package-archive');
    if (res.type != ResultType.done) {
      throw Exception('Instalacija nije pokrenuta: ${res.message}');
    }
  }
}

class ReleaseInfo {
  ReleaseInfo({
    required this.tagName,
    required this.apkUrl,
    required this.apkAssetName,
    required this.apkSize,
    required this.publishedAt,
  });

  final String tagName;
  final String apkUrl;
  final String apkAssetName;
  final int apkSize;
  final DateTime? publishedAt;

  factory ReleaseInfo.fromJson(Map<String, dynamic> d) {
    final assets = (d['assets'] as List<dynamic>? ?? [])
        .map((a) => a as Map<String, dynamic>)
        .where((a) => (a['name'] as String? ?? '').endsWith('.apk'))
        .toList();
    if (assets.isEmpty) {
      throw Exception('Novo izdanje nema APK datoteku');
    }
    // Take the first (only) APK asset in the release.
    final apk = assets.first;
    return ReleaseInfo(
      tagName: d['tag_name'] as String? ?? '',
      apkUrl: apk['browser_download_url'] as String? ?? '',
      apkAssetName: apk['name'] as String? ?? 'solray.apk',
      apkSize: (apk['size'] as num?)?.toInt() ?? 0,
      publishedAt: DateTime.tryParse(d['published_at'] as String? ?? ''),
    );
  }

  String get version => tagName.replaceFirst(RegExp(r'^[vV]'), '');
}

// Debug assert helper kept off the hot path.
@visibleForTesting
bool updaterIsNewer(String latest, String current) => Updater.isNewer(latest, current);
