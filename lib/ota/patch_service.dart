import 'dart:convert';

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

class PatchService {
  /// Patch history for the installed build number, newest first.
  static Future<List<PatchEntry>> fetchPatches() async {
    final myCode = await FlutterPatcher.appVersionCode;
    // Cache-buster: GitHub Pages caches files for up to ~10 minutes.
    final uri = Uri.parse(
      '$kPatchBaseUrl/patches.json?t=${DateTime.now().millisecondsSinceEpoch}',
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 10));
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
