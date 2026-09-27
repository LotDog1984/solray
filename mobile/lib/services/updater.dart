import 'dart:async';
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

  /// 1.13.2: api.github.com limits unauthenticated requests per IP — two
  /// phones on the same Wi-Fi share that budget, and when it runs out the
  /// API answers 403 and the app showed "GitHub nedostupan". Every request
  /// now sends a browser-like User-Agent (GitHub requires one), Accept, and
  /// a cache-buster so no intermediate proxy can serve a stale 304.
  static const Map<String, String> _headers = {
    'User-Agent': 'MyTeam-Mobile-Updater',
    'Accept': 'application/vnd.github+json',
    'Cache-Control': 'no-cache',
  };

  /// Latest release cached briefly (1.13.2): a check that succeeded less
  /// than 5 minutes ago is reused, so several phones on the same IP or a
  /// user tapping the button twice doesn't burn the per-IP rate budget.
  static ReleaseInfo? _cachedRelease;
  static DateTime _cachedAt = DateTime.fromMillisecondsSinceEpoch(0);
  static Duration get cacheTtl => const Duration(minutes: 5);

  /// Reset the cache (tests).
  @visibleForTesting
  static void clearCache() {
    _cachedRelease = null;
    _cachedAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  static String? _currentVersion;

  /// This app's version (e.g. "1.6.3"), read from the Android build config.
  static Future<String> currentVersion() async {
    if (_currentVersion != null) return _currentVersion!;
    final info = await PackageInfo.fromPlatform();
    _currentVersion = info.version;
    return _currentVersion!;
  }

  /// Info about the newest published release, or null when GitHub is
  /// unreachable / rate-limited / the repo has no releases. [lastError] (1.13.2)
  /// receives a short human-readable reason when null is returned, so the
  /// settings screen can show WHAT went wrong instead of a bare failure.
  static Future<ReleaseInfo?> latestRelease({void Function(String reason)? lastError}) async {
    final cached = _cachedRelease;
    if (cached != null && DateTime.now().difference(_cachedAt) < cacheTtl) {
      return cached;
    }
    // One immediate attempt + one short-delayed retry for TRANSIENT failures
    // (a flaky phone network right after wake used to fail the whole check on
    // the first blip). Definitive HTTP answers (403 rate limit, 404 no
    // release) are not retried — they would just repeat.
    for (var attempt = 0; attempt < 2; attempt++) {
      var transient = false;
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      try {
        final res = await http
            .get(
              Uri.parse('https://api.github.com/repos/$owner/$repo/releases/latest')
                  .replace(queryParameters: {'_': DateTime.now().millisecondsSinceEpoch.toString()}),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) {
          final d = jsonDecode(res.body) as Map<String, dynamic>;
          final release = ReleaseInfo.fromJson(d);
          _cachedRelease = release;
          _cachedAt = DateTime.now();
          return release;
        }
        // Distinguish the failure modes instead of one generic "unavailable":
        // 403 = rate limit (the shared-IP case), 404 = no releases, anything
        // else is reported verbatim for the diagnostics screen.
        if (res.statusCode >= 500) {
          transient = true;
          lastError?.call('GitHub ima problema (HTTP ${res.statusCode}). Pokušajte ponovno.');
        } else if (res.statusCode == 403) {
          final remaining = res.headers['x-ratelimit-remaining'];
          final reset = int.tryParse(res.headers['x-ratelimit-reset'] ?? '') ?? 0;
          final retryIn = reset > 0
              ? ' Pokušajte ponovno za ${((reset - DateTime.now().millisecondsSinceEpoch / 1000).ceil()).clamp(1, 60)} min.'
              : '';
          lastError?.call(
              'GitHub je privremeno odbio provjeru (HTTP 403${remaining != null ? ', preostalo zahtjeva: $remaining' : ''}).$retryIn');
        } else if (res.statusCode == 404) {
          lastError?.call('GitHub nema objavljeno izdanje (release) za ovu aplikaciju.');
        } else {
          lastError?.call('GitHub je odgovorio s HTTP ${res.statusCode}.');
        }
      } on TimeoutException {
        transient = true;
        lastError?.call('GitHub se ne javlja (istek vremena). Provjerite internetsku vezu.');
      } on SocketException {
        transient = true;
        lastError?.call('Nema pristupa GitHubu (mreža/DNS). Provjerite internetsku vezu.');
      } catch (e) {
        transient = true;
        lastError?.call('Greška pri provjeri: $e');
      }
      // 4xx answers are definitive for this minute — don't burn a retry on them.
      if (!transient) break;
    }
    return null;
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
