import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:yaml/yaml.dart';

const _manifestSchemaVersion = 1;
const _allowedHostedUrl = 'https://pub.dev';
const _licenseFileNames = <String>[
  'LICENSE',
  'LICENSE.txt',
  'LICENSE.md',
  'COPYING',
  'COPYING.txt',
  'NOTICE',
  'NOTICE.txt',
];

/// A validation error that prevents trustworthy release metadata generation.
final class ReleaseMetadataException implements Exception {
  /// Creates an audit exception with a user-facing [message].
  const ReleaseMetadataException(this.message);

  /// Describes the failed release-readiness requirement.
  final String message;

  @override
  String toString() => 'ReleaseMetadataException: $message';
}

/// A single dependency captured from `pubspec.lock`.
final class LockedDependency {
  /// Creates an immutable dependency record.
  const LockedDependency({
    required this.name,
    required this.version,
    required this.relationship,
    required this.source,
    required this.sourceUrl,
  });

  /// Package name from the lockfile.
  final String name;

  /// Exact locked package version.
  final String version;

  /// Pub relationship such as `direct main`, `direct dev`, or `transitive`.
  final String relationship;

  /// Pub source. Only `hosted` and `sdk` are accepted by this project.
  final String source;

  /// Hosted registry URL, or the SDK identifier for SDK packages.
  final String sourceUrl;
}

/// A resolved license file with a path safe to expose in generated reports.
final class ResolvedLicense {
  /// Creates a resolved license reference.
  const ResolvedLicense({required this.file, required this.displayPath});

  /// Local file used while generating the report.
  final File file;

  /// Non-absolute path written to release metadata.
  final String displayPath;
}

/// Generated release metadata and the files written to disk.
final class ReleaseMetadataResult {
  /// Creates a completed generation result.
  const ReleaseMetadataResult({
    required this.dependencyCount,
    required this.uniqueLicenseCount,
    required this.manifestFile,
    required this.noticesFile,
  });

  /// Number of locked dependencies included in the manifest.
  final int dependencyCount;

  /// Number of distinct license texts after SHA-256 de-duplication.
  final int uniqueLicenseCount;

  /// Machine-readable dependency snapshot.
  final File manifestFile;

  /// Human-readable, de-duplicated third-party notices.
  final File noticesFile;
}

/// Parses and validates the locked dependency graph.
List<LockedDependency> parseLockedDependencies(String lockfileContents) {
  final Object? document;
  try {
    document = loadYaml(lockfileContents);
  } on YamlException catch (error) {
    throw ReleaseMetadataException('pubspec.lock is invalid YAML: $error');
  }

  if (document is! YamlMap || document['packages'] is! YamlMap) {
    throw const ReleaseMetadataException(
      'pubspec.lock must contain a packages map.',
    );
  }

  final dependencies = <LockedDependency>[];
  final packages = document['packages'] as YamlMap;
  for (final entry in packages.entries) {
    final name = entry.key;
    final details = entry.value;
    if (name is! String || details is! YamlMap) {
      throw const ReleaseMetadataException(
        'pubspec.lock contains an invalid package entry.',
      );
    }

    final source = details['source'];
    final version = details['version'];
    final relationship = details['dependency'];
    if (source is! String || version is! String || relationship is! String) {
      throw ReleaseMetadataException(
        'Dependency "$name" is missing source, version, or relationship.',
      );
    }

    final description = details['description'];
    final String sourceUrl;
    switch (source) {
      case 'hosted':
        if (description is! YamlMap || description['url'] is! String) {
          throw ReleaseMetadataException(
            'Hosted dependency "$name" has no registry URL.',
          );
        }
        sourceUrl = description['url'] as String;
        if (sourceUrl != _allowedHostedUrl) {
          throw ReleaseMetadataException(
            'Hosted dependency "$name" uses untrusted registry '
            '"$sourceUrl"; only $_allowedHostedUrl is allowed.',
          );
        }
      case 'sdk':
        if (description is! String || description.isEmpty) {
          throw ReleaseMetadataException(
            'SDK dependency "$name" has no SDK identifier.',
          );
        }
        sourceUrl = description;
      default:
        throw ReleaseMetadataException(
          'Dependency "$name" uses unsupported source "$source". '
          'Git, path, and unknown sources are not allowed.',
        );
    }

    dependencies.add(
      LockedDependency(
        name: name,
        version: version,
        relationship: relationship,
        source: source,
        sourceUrl: sourceUrl,
      ),
    );
  }

  dependencies.sort((left, right) => left.name.compareTo(right.name));
  return dependencies;
}

/// Reads package roots from `.dart_tool/package_config.json`.
Map<String, Directory> readPackageRoots(File packageConfigFile) {
  final Object? document;
  try {
    document = jsonDecode(packageConfigFile.readAsStringSync());
  } on FileSystemException catch (error) {
    throw ReleaseMetadataException(
      'Cannot read ${packageConfigFile.path}: ${error.message}',
    );
  } on FormatException catch (error) {
    throw ReleaseMetadataException(
      '${packageConfigFile.path} is invalid JSON: ${error.message}',
    );
  }

  if (document is! Map<String, dynamic> || document['packages'] is! List) {
    throw ReleaseMetadataException(
      '${packageConfigFile.path} must contain a packages list.',
    );
  }

  final roots = <String, Directory>{};
  for (final package in document['packages'] as List<dynamic>) {
    if (package is! Map<String, dynamic> ||
        package['name'] is! String ||
        package['rootUri'] is! String) {
      throw ReleaseMetadataException(
        '${packageConfigFile.path} contains an invalid package entry.',
      );
    }

    final rootUri = packageConfigFile.absolute.uri.resolve(
      package['rootUri'] as String,
    );
    if (rootUri.scheme != 'file') {
      throw ReleaseMetadataException(
        'Package "${package['name']}" uses non-file root URI "$rootUri".',
      );
    }
    roots[package['name'] as String] = Directory.fromUri(rootUri);
  }
  return roots;
}

/// Finds all recognized license and notice files for [dependency].
///
/// SDK packages without a package-local license inherit the Flutter SDK root
/// license. Hosted dependencies never search outside their package directory.
List<ResolvedLicense> resolveDependencyLicenses(
  LockedDependency dependency,
  Directory packageRoot,
) {
  final packageLicenses = _findLicenseFiles(packageRoot).map(
    (file) => ResolvedLicense(
      file: file,
      displayPath: '$dependency.name/${_basename(file.path)}',
    ),
  );
  final resolved = packageLicenses.toList(growable: false);
  if (resolved.isNotEmpty || dependency.source != 'sdk') {
    return resolved;
  }

  Directory current = packageRoot.parent;
  for (var depth = 0; depth < 8; depth += 1) {
    if (_isFlutterSdkRoot(current)) {
      return _findLicenseFiles(current)
          .map(
            (file) => ResolvedLicense(
              file: file,
              displayPath: 'flutter-sdk/${_basename(file.path)}',
            ),
          )
          .toList(growable: false);
    }
    if (current.parent.path == current.path) {
      break;
    }
    current = current.parent;
  }
  return const [];
}

/// Generates dependency and license reports for an unsigned release build.
Future<ReleaseMetadataResult> generateReleaseMetadata({
  required File lockfile,
  required File packageConfigFile,
  required Directory outputDirectory,
  DateTime? generatedAt,
}) async {
  final dependencies = parseLockedDependencies(lockfile.readAsStringSync());
  final packageRoots = readPackageRoots(packageConfigFile);
  final lockfileHash = await _sha256(lockfile.readAsBytesSync());
  final licenseGroups = <String, _LicenseGroup>{};
  final manifestDependencies = <Map<String, Object?>>[];

  for (final dependency in dependencies) {
    final packageRoot = packageRoots[dependency.name];
    if (packageRoot == null || !packageRoot.existsSync()) {
      throw ReleaseMetadataException(
        'Dependency "${dependency.name}" has no readable package root. '
        'Run flutter pub get before generating release metadata.',
      );
    }

    final licenses = resolveDependencyLicenses(dependency, packageRoot);
    if (licenses.isEmpty) {
      throw ReleaseMetadataException(
        'Dependency "${dependency.name}" has no recognized license file.',
      );
    }

    final manifestLicenses = <Map<String, String>>[];
    for (final license in licenses) {
      final bytes = license.file.readAsBytesSync();
      final hash = await _sha256(bytes);
      final group = licenseGroups.putIfAbsent(
        hash,
        () => _LicenseGroup(hash: hash, contents: utf8.decode(bytes)),
      );
      group.packages.add(dependency.name);
      group.sourceFiles.add(license.displayPath);
      manifestLicenses.add({'file': license.displayPath, 'sha256': hash});
    }

    manifestDependencies.add({
      'name': dependency.name,
      'version': dependency.version,
      'relationship': dependency.relationship,
      'source': {'type': dependency.source, 'location': dependency.sourceUrl},
      'licenses': manifestLicenses,
    });
  }

  final timestamp = (generatedAt ?? DateTime.now().toUtc()).toUtc();
  final sortedGroups = licenseGroups.values.toList()
    ..sort((left, right) => left.hash.compareTo(right.hash));
  outputDirectory.createSync(recursive: true);

  final manifestFile = File(
    _join(outputDirectory.path, 'dependency-manifest.json'),
  );
  final manifest = <String, Object?>{
    'schemaVersion': _manifestSchemaVersion,
    'generatedAt': timestamp.toIso8601String(),
    'lockfile': {'file': 'pubspec.lock', 'sha256': lockfileHash},
    'dependencyCount': dependencies.length,
    'uniqueLicenseCount': sortedGroups.length,
    'dependencies': manifestDependencies,
    'licenseGroups': sortedGroups
        .map(
          (group) => {
            'sha256': group.hash,
            'packages': group.sortedPackages,
            'sourceFiles': group.sortedSourceFiles,
          },
        )
        .toList(growable: false),
  };
  manifestFile.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );

  final noticesFile = File(
    _join(outputDirectory.path, 'THIRD_PARTY_NOTICES.txt'),
  );
  noticesFile.writeAsStringSync(
    _buildNotices(timestamp: timestamp, groups: sortedGroups),
  );

  return ReleaseMetadataResult(
    dependencyCount: dependencies.length,
    uniqueLicenseCount: sortedGroups.length,
    manifestFile: manifestFile,
    noticesFile: noticesFile,
  );
}

/// Command-line entry point used by local checks and GitHub Actions.
Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln('Usage: dart run tool/release_metadata.dart');
    exitCode = 64;
    return;
  }

  try {
    final result = await generateReleaseMetadata(
      lockfile: File('pubspec.lock'),
      packageConfigFile: File('.dart_tool/package_config.json'),
      outputDirectory: Directory('build/release-metadata'),
    );
    stdout.writeln(
      'Release metadata generated for ${result.dependencyCount} dependencies '
      'with ${result.uniqueLicenseCount} unique license texts.',
    );
    stdout.writeln('Manifest: ${result.manifestFile.path}');
    stdout.writeln('Notices: ${result.noticesFile.path}');
  } on ReleaseMetadataException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  } on FileSystemException catch (error) {
    stderr.writeln('Release metadata generation failed: ${error.message}');
    exitCode = 1;
  }
}

final class _LicenseGroup {
  _LicenseGroup({required this.hash, required this.contents});

  final String hash;
  final String contents;
  final Set<String> packages = <String>{};
  final Set<String> sourceFiles = <String>{};

  List<String> get sortedPackages => packages.toList()..sort();

  List<String> get sortedSourceFiles => sourceFiles.toList()..sort();
}

List<File> _findLicenseFiles(Directory directory) {
  final files = <File>[];
  for (final name in _licenseFileNames) {
    final file = File(_join(directory.path, name));
    if (file.existsSync()) {
      files.add(file);
    }
  }
  return files;
}

bool _isFlutterSdkRoot(Directory directory) {
  final hasLicense = File(_join(directory.path, 'LICENSE')).existsSync();
  final hasUnixLauncher = File(
    _join(directory.path, _join('bin', 'flutter')),
  ).existsSync();
  final hasWindowsLauncher = File(
    _join(directory.path, _join('bin', 'flutter.bat')),
  ).existsSync();
  return hasLicense && (hasUnixLauncher || hasWindowsLauncher);
}

Future<String> _sha256(List<int> bytes) async {
  final hash = await Sha256().hash(bytes);
  return hash.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

String _buildNotices({
  required DateTime timestamp,
  required List<_LicenseGroup> groups,
}) {
  final output = StringBuffer()
    ..writeln('TOTP Vault Third-Party Notices')
    ..writeln('Generated: ${timestamp.toIso8601String()}')
    ..writeln()
    ..writeln('This report is generated from the locked dependency snapshot.')
    ..writeln('It is not legal advice and does not replace manual review.')
    ..writeln();

  for (final group in groups) {
    output
      ..writeln('=' * 78)
      ..writeln('License SHA-256: ${group.hash}')
      ..writeln('Packages: ${group.sortedPackages.join(', ')}')
      ..writeln('Source files: ${group.sortedSourceFiles.join(', ')}')
      ..writeln('-' * 78)
      ..writeln(group.contents.trimRight())
      ..writeln();
  }
  return output.toString();
}

String _join(String first, String second) {
  final separator = Platform.pathSeparator;
  if (first.endsWith(separator)) {
    return '$first$second';
  }
  return '$first$separator$second';
}

String _basename(String path) => path.split(Platform.pathSeparator).last;
