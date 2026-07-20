import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final repositoryRoot = Directory.current;

  test(
    'personal package definitions keep platform security controls intact',
    () {
      final macScript = File(
        '${repositoryRoot.path}/tool/package_macos_dmg.sh',
      ).readAsStringSync();
      final windowsScript = File(
        '${repositoryRoot.path}/tool/package_windows_exe.ps1',
      ).readAsStringSync();
      final innoDefinition = File(
        '${repositoryRoot.path}/windows/installer/google_code.iss',
      ).readAsStringSync();

      expect(macScript, contains('hdiutil create'));
      expect(macScript, contains('hdiutil verify'));
      expect(macScript, contains('--codesign-identity'));
      expect(macScript, contains('GOOGLE_CODE_CODESIGN_IDENTITY'));
      expect(macScript, contains('TOTP Vault Local Signing'));
      expect(macScript, contains('security find-identity'));
      expect(
        macScript,
        contains('--preserve-metadata=identifier,entitlements'),
      );
      expect(macScript, contains('codesign --verify --deep --strict'));
      expect(macScript, contains('ln -s /Applications'));
      expect(macScript, isNot(contains('xattr -d')));
      expect(macScript, isNot(contains('spctl --master-disable')));

      expect(windowsScript, contains('Inno Setup 6'));
      expect(windowsScript, contains('Get-AuthenticodeSignature'));
      expect(windowsScript, contains('SmartScreen is not bypassed'));
      expect(windowsScript, isNot(contains('Set-ExecutionPolicy')));
      expect(windowsScript, isNot(contains('Add-MpPreference')));

      expect(innoDefinition, contains('PrivilegesRequired=lowest'));
      expect(innoDefinition, contains(r'DefaultDirName={localappdata}'));
      expect(innoDefinition, contains('CloseApplications=yes'));
      expect(innoDefinition, contains('RestartApplications=no'));
      expect(innoDefinition, contains('compiler:Default.isl'));
      expect(innoDefinition, isNot(contains('ChineseSimplified.isl')));
      expect(innoDefinition, isNot(contains('PrivilegesRequired=admin')));
      expect(innoDefinition, isNot(contains(r'{userappdata}')));
      expect(innoDefinition, isNot(contains(r'DestDir: "{userappdata}')));
      expect(innoDefinition, isNot(contains(r'DestDir: "{commonappdata}')));
    },
  );

  test(
    'macOS packager creates a mountable DMG without modifying external data',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'google-code-dmg-test-',
      );
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });

      final app = Directory('${temp.path}/Fixture.app');
      final executable = File('${app.path}/Contents/MacOS/google_code');
      await executable.parent.create(recursive: true);
      await executable.writeAsString('#!/bin/sh\nexit 0\n');
      await Process.run('chmod', ['+x', executable.path]);
      await File('${app.path}/Contents/Info.plist').writeAsString('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.gengyujian.googleCode.fixture</string>
<key>CFBundleExecutable</key><string>google_code</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
''');
      final sign = await Process.run('codesign', [
        '--force',
        '--deep',
        '--sign',
        '-',
        app.path,
      ]);
      expect(sign.exitCode, 0, reason: '${sign.stdout}\n${sign.stderr}');

      final externalVault = File('${temp.path}/personal.gcvault');
      await externalVault.writeAsString('preserve-me');
      final output = '${temp.path}/TOTPVault-test.dmg';
      final script = '${repositoryRoot.path}/tool/package_macos_dmg.sh';

      final dryRun = await Process.run('bash', [
        script,
        '--source',
        app.path,
        '--output',
        output,
        '--skip-build',
        '--dry-run',
      ], workingDirectory: repositoryRoot.path);
      expect(dryRun.exitCode, 0, reason: '${dryRun.stdout}\n${dryRun.stderr}');
      expect(await File(output).exists(), isFalse);

      final package = await Process.run('bash', [
        script,
        '--source',
        app.path,
        '--output',
        output,
        '--skip-build',
      ], workingDirectory: repositoryRoot.path);
      expect(
        package.exitCode,
        0,
        reason: '${package.stdout}\n${package.stderr}',
      );
      expect(await File(output).exists(), isTrue);
      expect(
        await File('$output.sha256').readAsString(),
        contains('TOTPVault-test.dmg'),
      );
      expect(await externalVault.readAsString(), 'preserve-me');

      final mount = Directory('${temp.path}/mount');
      await mount.create();
      final attach = await Process.run('hdiutil', [
        'attach',
        '-readonly',
        '-nobrowse',
        '-mountpoint',
        mount.path,
        output,
      ]);
      expect(attach.exitCode, 0, reason: '${attach.stdout}\n${attach.stderr}');
      try {
        expect(
          await File(
            '${mount.path}/TOTP Vault.app/Contents/MacOS/google_code',
          ).exists(),
          isTrue,
        );
        expect(
          Link('${mount.path}/Applications').targetSync(),
          '/Applications',
        );
      } finally {
        final detach = await Process.run('hdiutil', ['detach', mount.path]);
        expect(
          detach.exitCode,
          0,
          reason: '${detach.stdout}\n${detach.stderr}',
        );
      }
    },
    skip: !Platform.isMacOS,
  );
}
