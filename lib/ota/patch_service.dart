import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_patcher/flutter_patcher.dart';
import 'package:http/http.dart' as http;

import 'ota_config.dart';

/// One entry of `patches.json`, written by the "OTA patch" GitHub workflow.
class PatchEntry {
  PatchEntry({
    required this.id,
    required this.title,
    required this.file,
    required this.createdAt,
    required this.versionCode,
  });

  final String id; // short commit SHA
  final String title; // PR title / commit message
  final String file; // e.g. 1-arm64-v8a.fptc
  final DateTime createdAt;
  final int versionCode; // build number this patch targets

  factory PatchEntry.fromJson(Map<String, dynamic> j) => PatchEntry(
        id: j['id'] as String,
        title: j['title'] as String,
        file: j['file'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        versionCode: j['versionCode'] as int,
      );
}

/// Fetches patch files from GitHub Pages ourselves instead of using
/// `FlutterPatcher.checkUpdate()` / `applyPatch()`.
///
/// Why: Dart's HttpClient asks for gzip, and GitHub Pages then gzips the
/// .fptc file and applies the `Range: bytes=0-145` header to the *compressed*
/// bytes. flutter_patcher unpacks fewer than 146 bytes and fails with
/// "Not a patch file". Asking for `Accept-Encoding: identity` returns the raw
/// bytes, and a missing file then correctly returns 404 (not 503).
class PatchService {
  static const _headerSize = 146;
  static const _timeout = Duration(seconds: 15);
  static const _noGzip = {'Accept-Encoding': 'identity'};

  static Future<Uri> _patchUri() async {
    final target = await FlutterPatcher.patchTarget;
    return Uri.parse('$kPatchBaseUrl/${target.fileName}');
  }

  /// True when the server has a patch this app would accept (newer than the
  /// installed one, built for this exact APK).
  static Future<bool> hasUpdate() async {
    final res = await http
        .get(
          await _patchUri(),
          headers: {..._noGzip, 'Range': 'bytes=0-${_headerSize - 1}'},
        )
        .timeout(_timeout);
    if (res.statusCode == 404) return false; // no patch for this build yet
    if (res.statusCode != 200 && res.statusCode != 206) {
      throw Exception('Patch check: HTTP ${res.statusCode}');
    }
    if (res.bodyBytes.length < _headerSize) {
      throw Exception('Patch check: only ${res.bodyBytes.length} bytes');
    }
    final inspection = await FlutterPatcher.inspectPatch(
      res.bodyBytes.sublist(0, _headerSize),
    );
    return inspection.fresh;
  }

  /// Downloads the whole patch file for this build.
  static Future<Uint8List> downloadPatch() async {
    final res = await http
        .get(await _patchUri(), headers: _noGzip)
        .timeout(const Duration(minutes: 2));
    if (res.statusCode != 200) {
      throw Exception('Patch download: HTTP ${res.statusCode}');
    }
    return res.bodyBytes;
  }

  /// Patch history for the installed build number, newest first.
  static Future<List<PatchEntry>> fetchPatches() async {
    final myCode = await FlutterPatcher.appVersionCode;
    // Cache-buster: GitHub Pages caches files for up to ~10 minutes.
    final uri = Uri.parse(
      '$kPatchBaseUrl/patches.json?t=${DateTime.now().millisecondsSinceEpoch}',
    );
    final res = await http.get(uri).timeout(_timeout);
    if (res.statusCode == 404) return [];
    if (res.statusCode != 200) {
      throw Exception('patches.json: HTTP ${res.statusCode}');
    }
    return (jsonDecode(res.body) as List)
        .map((e) => PatchEntry.fromJson(e as Map<String, dynamic>))
        .where((p) => myCode == null || p.versionCode == myCode)
        .toList();
  }
}
