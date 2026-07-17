import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/release_metadata.dart';

void main() {
  group('parseLockedDependencies', () {
    test('accepts pub.dev hosted and Flutter SDK dependencies', () {
      final dependencies = parseLockedDependencies('''
packages:
  alpha:
    dependency: "direct main"
    description:
      name: alpha
      sha256: abc
      url: "https://pub.dev"
    source: hosted
    version: "1.2.3"
  flutter:
    dependency: "direct main"
    description: flutter
    source: sdk
    version: "0.0.0"
''');

      expect(dependencies, hasLength(2));
      expect(dependencies.first.name, 'alpha');
      expect(dependencies.first.sourceUrl, 'https://pub.dev');
      expect(dependencies.last.name, 'flutter');
      expect(dependencies.last.sourceUrl, 'flutter');
    });

    test('rejects a hosted dependency outside pub.dev', () {
      expect(
        () => parseLockedDependencies('''
packages:
  alpha:
    dependency: transitive
    description:
      name: alpha
      url: "https://mirror.example.com"
    source: hosted
    version: "1.0.0"
'''),
        throwsA(
          isA<ReleaseMetadataException>().having(
            (error) => error.message,
            'message',
            contains('untrusted registry'),
          ),
        ),
      );
    });

    test('rejects git and path dependency sources', () {
      expect(
        () => parseLockedDependencies('''
packages:
  alpha:
    dependency: transitive
    description:
      path: .
      url: "https://example.com/repository.git"
    source: git
    version: "1.0.0"
'''),
        throwsA(
          isA<ReleaseMetadataException>().having(
            (error) => error.message,
            'message',
            contains('unsupported source'),
          ),
        ),
      );
    });
  });

  test('readPackageRoots resolves package-config relative URIs', () {
    final sandbox = Directory.systemTemp.createTempSync('package-roots-');
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final packageRoot = Directory('${sandbox.path}/package')..createSync();
    final configDirectory = Directory('${sandbox.path}/.dart_tool')
      ..createSync();
    final configFile = File('${configDirectory.path}/package_config.json')
      ..writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {'name': 'alpha', 'rootUri': '../package', 'packageUri': 'lib/'},
          ],
        }),
      );

    final roots = readPackageRoots(configFile);

    expect(roots['alpha']?.absolute.path, packageRoot.absolute.path);
  });

  group('resolveDependencyLicenses', () {
    test('does not search parent directories for hosted dependencies', () {
      final sandbox = Directory.systemTemp.createTempSync('license-hosted-');
      addTearDown(() => sandbox.deleteSync(recursive: true));
      File('${sandbox.path}/LICENSE').writeAsStringSync('parent license');
      final package = Directory('${sandbox.path}/package')..createSync();

      final licenses = resolveDependencyLicenses(
        const LockedDependency(
          name: 'alpha',
          version: '1.0.0',
          relationship: 'transitive',
          source: 'hosted',
          sourceUrl: 'https://pub.dev',
        ),
        package,
      );

      expect(licenses, isEmpty);
    });

    test('uses Flutter SDK root license for SDK packages', () {
      final sandbox = Directory.systemTemp.createTempSync('license-sdk-');
      addTearDown(() => sandbox.deleteSync(recursive: true));
      File('${sandbox.path}/LICENSE').writeAsStringSync('Flutter license');
      final bin = Directory('${sandbox.path}/bin')..createSync();
      File('${bin.path}/flutter').writeAsStringSync('launcher');
      final package = Directory('${sandbox.path}/packages/flutter_test')
        ..createSync(recursive: true);

      final licenses = resolveDependencyLicenses(
        const LockedDependency(
          name: 'flutter_test',
          version: '0.0.0',
          relationship: 'direct dev',
          source: 'sdk',
          sourceUrl: 'flutter',
        ),
        package,
      );

      expect(licenses, hasLength(1));
      expect(licenses.single.displayPath, 'flutter-sdk/LICENSE');
    });
  });

  test(
    'generator de-duplicates license content and writes safe metadata',
    () async {
      final sandbox = Directory.systemTemp.createTempSync('release-metadata-');
      addTearDown(() => sandbox.deleteSync(recursive: true));
      final alpha = Directory('${sandbox.path}/packages/alpha')
        ..createSync(recursive: true);
      final beta = Directory('${sandbox.path}/packages/beta')
        ..createSync(recursive: true);
      File('${alpha.path}/LICENSE').writeAsStringSync('Shared license\n');
      File('${beta.path}/LICENSE.txt').writeAsStringSync('Shared license\n');

      final lockfile = File('${sandbox.path}/pubspec.lock')
        ..writeAsStringSync('''
packages:
  alpha:
    dependency: "direct main"
    description:
      name: alpha
      url: "https://pub.dev"
    source: hosted
    version: "1.0.0"
  beta:
    dependency: transitive
    description:
      name: beta
      url: "https://pub.dev"
    source: hosted
    version: "2.0.0"
''');
      final packageConfigDirectory = Directory('${sandbox.path}/.dart_tool')
        ..createSync();
      final packageConfig =
          File('${packageConfigDirectory.path}/package_config.json')
            ..writeAsStringSync(
              jsonEncode({
                'configVersion': 2,
                'packages': [
                  {
                    'name': 'alpha',
                    'rootUri': alpha.uri.toString(),
                    'packageUri': 'lib/',
                  },
                  {
                    'name': 'beta',
                    'rootUri': beta.uri.toString(),
                    'packageUri': 'lib/',
                  },
                ],
              }),
            );

      final result = await generateReleaseMetadata(
        lockfile: lockfile,
        packageConfigFile: packageConfig,
        outputDirectory: Directory('${sandbox.path}/output'),
        generatedAt: DateTime.utc(2026, 7, 17),
      );

      expect(result.dependencyCount, 2);
      expect(result.uniqueLicenseCount, 1);
      final manifest =
          jsonDecode(result.manifestFile.readAsStringSync())
              as Map<String, dynamic>;
      expect(manifest['generatedAt'], '2026-07-17T00:00:00.000Z');
      expect(manifest['uniqueLicenseCount'], 1);
      expect(manifest['licenseGroups'][0]['packages'], <String>[
        'alpha',
        'beta',
      ]);
      expect(
        result.manifestFile.readAsStringSync(),
        isNot(contains(sandbox.path)),
      );
      expect(result.noticesFile.readAsStringSync(), contains('Shared license'));
    },
  );

  test('generator fails when a dependency has no package root', () async {
    final sandbox = Directory.systemTemp.createTempSync(
      'release-missing-root-',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final lockfile = File('${sandbox.path}/pubspec.lock')
      ..writeAsStringSync('''
packages:
  missing:
    dependency: transitive
    description:
      name: missing
      url: "https://pub.dev"
    source: hosted
    version: "1.0.0"
''');
    final packageConfig = File('${sandbox.path}/package_config.json')
      ..writeAsStringSync(
        jsonEncode({'configVersion': 2, 'packages': <Object>[]}),
      );

    expect(
      () => generateReleaseMetadata(
        lockfile: lockfile,
        packageConfigFile: packageConfig,
        outputDirectory: Directory('${sandbox.path}/output'),
      ),
      throwsA(
        isA<ReleaseMetadataException>().having(
          (error) => error.message,
          'message',
          contains('no readable package root'),
        ),
      ),
    );
  });
}
