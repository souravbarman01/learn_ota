import 'package:flutter/material.dart';
import 'package:flutter_patcher/flutter_patcher.dart';

import 'app_restart.dart';
import 'patch_service.dart';

class OtaScreen extends StatefulWidget {
  const OtaScreen({super.key});

  @override
  State<OtaScreen> createState() => _OtaScreenState();
}

class _OtaScreenState extends State<OtaScreen> {
  bool _loading = true;
  bool _available = false; // false in debug / `flutter run` builds
  String? _installed; // currently installed patch, if any
  List<PatchEntry> _patches = [];
  bool _hasUpdate = false;
  String? _error;
  String? _progress; // non-null while installing

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final errors = <String>[];
    try {
      // Each step is guarded on its own, so one failure doesn't hide the
      // others (e.g. a failed update check no longer shows "disabled").
      final available = await FlutterPatcher.isAvailable;
      final installed = await FlutterPatcher.currentVersion;
      if (mounted) {
        setState(() {
          _available = available;
          _installed = installed;
        });
      }

      var hasUpdate = false;
      if (available) {
        try {
          hasUpdate = await PatchService.hasUpdate();
        } catch (e) {
          errors.add('Update check failed: $e');
        }
      }

      var patches = <PatchEntry>[];
      try {
        patches = await PatchService.fetchPatches();
      } catch (e) {
        errors.add('Could not load patch list: $e');
      }

      if (!mounted) return;
      setState(() {
        _hasUpdate = hasUpdate;
        _patches = patches;
      });
    } catch (e) {
      errors.add('$e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = errors.isEmpty ? null : errors.join('\n');
        });
      }
    }
  }

  Future<void> _install() async {
    if (!_hasUpdate) return;

    final accept = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Install update?'),
        content: const Text(
          'The update will be downloaded and the app will restart.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
    if (accept != true || !mounted) return;

    setState(() {
      _error = null;
      _progress = 'Downloading…';
    });
    final PatchApplyResult result;
    try {
      final bytes = await PatchService.downloadPatch();
      if (!mounted) return;
      setState(() => _progress = 'Verifying and installing…');
      result = await FlutterPatcher.applyPatchBytes(bytes);
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = 'Download failed: $e';
        });
      }
      return;
    }
    if (!mounted) return;

    if (!result.ok) {
      setState(() {
        _progress = null;
        _error = 'Install failed: ${result.error} ${result.message ?? ''}';
      });
      return;
    }

    setState(() => _progress = 'Installed. Restarting…');
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final restarted = await AppRestart.restart();
    if (restarted || !mounted) return;

    // Fallback (e.g. iOS): the patch applies on the next cold start.
    setState(() => _progress = null);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update installed'),
        content: const Text(
          'Fully close the app and open it again to apply the update.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _progress != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('OTA updates'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loading || busy ? null : _refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: Icon(
                  _available ? Icons.cloud_done : Icons.cloud_off,
                  color: _available ? Colors.green : Colors.grey,
                ),
                title: Text(
                  _available ? 'OTA patching enabled' : 'OTA patching disabled',
                ),
                subtitle: Text(
                  _available
                      ? 'Installed patch: ${_installed ?? 'none (store build)'}'
                      : 'Install the release APK built by the "Release host" '
                            'workflow. Debug builds cannot be patched.',
                ),
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            if (busy) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
              const SizedBox(height: 4),
              Text(_progress!),
            ],
            const SizedBox(height: 8),
            if (!_loading && _patches.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _hasUpdate
                      ? 'An update is available.'
                      : 'No updates available. Pull down to refresh.',
                  textAlign: TextAlign.center,
                ),
              ),
            // Update available but not in the list (e.g. list not deployed yet)
            if (_hasUpdate && _patches.isEmpty)
              Center(
                child: FilledButton.icon(
                  onPressed: busy ? null : _install,
                  icon: const Icon(Icons.download),
                  label: const Text('Download & install'),
                ),
              ),
            for (var i = 0; i < _patches.length; i++)
              Card(
                child: ListTile(
                  title: Text(_patches[i].title),
                  subtitle: Text(
                    '${_patches[i].id} • ${_patches[i].createdAt.toLocal()}',
                  ),
                  // Only the newest patch can be installed (sequence rule).
                  trailing: i > 0
                      ? const Text('Superseded')
                      : _hasUpdate
                      ? FilledButton(
                          onPressed: busy ? null : _install,
                          child: const Text('Install'),
                        )
                      : const Chip(label: Text('Up to date')),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
