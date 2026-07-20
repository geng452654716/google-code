import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final repository = Directory.current;
  final macInstaller = File('${repository.path}/tool/install_macos.sh');
  final windowsInstaller = File('${repository.path}/tool/install_windows.ps1');

  test('personal installer scripts expose the documented safety controls', () {
    final macSource = macInstaller.readAsStringSync();
    final windowsSource = windowsInstaller.readAsStringSync();

    expect(macSource, contains('--dry-run'));
    expect(macSource, contains('--uninstall'));
    expect(macSource, contains('--codesign-identity'));
    expect(macSource, contains('GOOGLE_CODE_CODESIGN_IDENTITY'));
    expect(macSource, contains('--preserve-metadata=identifier,entitlements'));
    expect(macSource, contains('--sign -'));
    expect(macSource, contains('codesign --verify --deep --strict'));
    expect(macSource, isNot(contains('xattr -d')));
    expect(macSource, contains('never removes com.apple.quarantine'));

    expect(windowsSource, contains(r'[switch]$DryRun'));
    expect(windowsSource, contains(r'[switch]$Uninstall'));
    expect(windowsSource, contains('WScript.Shell'));
    expect(windowsSource, isNot(contains('Set-ExecutionPolicy')));
  });

  test(
    'macOS installer rejects a missing source without writing destination',
    () async {
      final sandbox = Directory.systemTemp.createTempSync(
        'google-code-installer-missing-',
      );
      addTearDown(() => sandbox.deleteSync(recursive: true));
      final destination = '${sandbox.path}/TOTP Vault.app';

      final result = await Process.run('bash', <String>[
        macInstaller.path,
        '--source',
        '${sandbox.path}/Missing.app',
        '--destination',
        destination,
        '--skip-build',
      ]);

      expect(result.exitCode, isNot(0));
      expect('${result.stderr}', contains('Source app does not exist'));
      expect(Directory(destination).existsSync(), isFalse);
    },
    skip: !Platform.isMacOS,
  );

  test(
    'macOS dry run validates a signed source without installing it',
    () async {
      final fixture = await _createSignedMacAppFixture('dry-run');
      addTearDown(() => fixture.sandbox.deleteSync(recursive: true));
      final destination = '${fixture.sandbox.path}/Installed.app';

      final result = await Process.run('bash', <String>[
        macInstaller.path,
        '--source',
        fixture.app.path,
        '--destination',
        destination,
        '--skip-build',
        '--dry-run',
      ]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect('${result.stdout}', contains('Dry run complete'));
      expect(Directory(destination).existsSync(), isFalse);
    },
    skip: !Platform.isMacOS,
  );

  test(
    'macOS installer supports install, upgrade, and data-preserving uninstall',
    () async {
      final fixture = await _createSignedMacAppFixture('version-one');
      addTearDown(() => fixture.sandbox.deleteSync(recursive: true));
      final destination = Directory(
        '${fixture.sandbox.path}/Applications/TOTP Vault.app',
      );
      final userData = File('${fixture.sandbox.path}/vault.gcvault')
        ..writeAsStringSync('must survive uninstall');

      await _runMacInstaller(macInstaller, fixture.app, destination);
      expect(
        File(
          '${destination.path}/Contents/Resources/version.txt',
        ).readAsStringSync(),
        'version-one',
      );

      File(
        '${fixture.app.path}/Contents/Resources/version.txt',
      ).writeAsStringSync('version-two');
      await _signMacApp(fixture.app);
      await _runMacInstaller(macInstaller, fixture.app, destination);
      expect(
        File(
          '${destination.path}/Contents/Resources/version.txt',
        ).readAsStringSync(),
        'version-two',
      );
      expect(
        fixture.sandbox
            .listSync(recursive: true)
            .where(
              (entry) =>
                  entry.path.contains('.installing-') ||
                  entry.path.contains('.backup-'),
            ),
        isEmpty,
      );

      final uninstall = await Process.run('bash', <String>[
        macInstaller.path,
        '--destination',
        destination.path,
        '--uninstall',
      ]);
      expect(uninstall.exitCode, 0, reason: '${uninstall.stderr}');
      expect(destination.existsSync(), isFalse);
      expect(userData.readAsStringSync(), 'must survive uninstall');
    },
    skip: !Platform.isMacOS,
  );
}

Future<void> _runMacInstaller(
  File installer,
  Directory source,
  Directory destination,
) async {
  final result = await Process.run('bash', <String>[
    installer.path,
    '--source',
    source.path,
    '--destination',
    destination.path,
    '--skip-build',
  ]);
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
}

Future<({Directory sandbox, Directory app})> _createSignedMacAppFixture(
  String version,
) async {
  final sandbox = Directory.systemTemp.createTempSync(
    'google-code-installer-fixture-',
  );
  final app = Directory('${sandbox.path}/Fixture.app');
  final executable = File('${app.path}/Contents/MacOS/google_code');
  executable.parent.createSync(recursive: true);
  executable.writeAsStringSync('#!/bin/sh\nexit 0\n');
  await Process.run('chmod', <String>['+x', executable.path]);
  final resources = Directory('${app.path}/Contents/Resources')
    ..createSync(recursive: true);
  File('${resources.path}/version.txt').writeAsStringSync(version);
  File('${app.path}/Contents/Info.plist').writeAsStringSync(
    '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>google_code</string>
  <key>CFBundleIdentifier</key>
  <string>com.gengyujian.googleCode.installerFixture</string>
  <key>CFBundleName</key>
  <string>TOTP Vault Installer Fixture</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
</dict>
</plist>
''',
  );
  await _signMacApp(app);
  return (sandbox: sandbox, app: app);
}

Future<void> _signMacApp(Directory app) async {
  final result = await Process.run('codesign', <String>[
    '--force',
    '--deep',
    '--sign',
    '-',
    app.path,
  ]);
  if (result.exitCode != 0) {
    throw StateError('Failed to sign fixture: ${result.stderr}');
  }
}
