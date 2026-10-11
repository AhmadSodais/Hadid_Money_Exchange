import 'dart:io';

import 'package:flutter/foundation.dart';

import 'authorized_devices.dart';

/// Resolves local network adapter MAC addresses (Windows desktop).
class DeviceMacService {
  /// Returns unique normalized MAC strings found on this machine.
  Future<List<String>> readLocalMacs() async {
    if (!Platform.isWindows) {
      debugPrint('DeviceMacService: MAC check is Windows-only.');
      return const [];
    }

    final found = <String>{};

    await _collectFromGetmac(found);
    if (found.isEmpty) {
      await _collectFromPowerShell(found);
    }

    return found.toList(growable: false);
  }

  Future<void> _collectFromGetmac(Set<String> out) async {
    try {
      final result = await Process.run(
        'getmac',
        ['/FO', 'CSV', '/NH'],
        runInShell: true,
      );
      if (result.exitCode != 0) return;
      final stdout = '${result.stdout}';
      for (final line in stdout.split(RegExp(r'\r?\n'))) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        // "AA-BB-CC-DD-EE-FF","\Device\..."
        final match = RegExp(
          r'"([0-9A-Fa-f]{2}([-:])[0-9A-Fa-f]{2}(\2[0-9A-Fa-f]{2}){4})"',
        ).firstMatch(trimmed);
        if (match == null) continue;
        final n = AuthorizedDevices.normalizeMac(match.group(1)!);
        if (n != null) out.add(n);
      }
    } catch (e) {
      debugPrint('DeviceMacService getmac failed: $e');
    }
  }

  Future<void> _collectFromPowerShell(Set<String> out) async {
    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r"Get-NetAdapter | Where-Object { $_.MacAddress } | "
              r"ForEach-Object { $_.MacAddress }",
        ],
        runInShell: false,
      );
      if (result.exitCode != 0) return;
      for (final line in '${result.stdout}'.split(RegExp(r'\r?\n'))) {
        final n = AuthorizedDevices.normalizeMac(line.trim());
        if (n != null) out.add(n);
      }
    } catch (e) {
      debugPrint('DeviceMacService PowerShell failed: $e');
    }
  }
}
