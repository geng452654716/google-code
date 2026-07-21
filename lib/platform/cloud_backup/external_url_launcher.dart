import 'dart:io';

import 'cloud_backup_provider.dart';

/// Opens provider authorization pages without embedding a web view.
abstract interface class ExternalUrlLauncher {
  Future<void> open(Uri uri);
}

class DesktopExternalUrlLauncher implements ExternalUrlLauncher {
  const DesktopExternalUrlLauncher();

  @override
  Future<void> open(Uri uri) async {
    late final ProcessResult result;
    if (Platform.isMacOS) {
      result = await Process.run('/usr/bin/open', [uri.toString()]);
    } else if (Platform.isWindows) {
      result = await Process.run('rundll32.exe', [
        'url.dll,FileProtocolHandler',
        uri.toString(),
      ]);
    } else {
      throw const CloudBackupException('当前平台无法打开 GitHub 授权页面。');
    }
    if (result.exitCode != 0) {
      throw const CloudBackupException('无法打开 GitHub 授权页面。');
    }
  }
}
