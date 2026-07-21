import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final repositoryRoot = Directory.current;

  test('GitHub Release workflow keeps publishing gated and reproducible', () {
    final workflow = File(
      '${repositoryRoot.path}/.github/workflows/release.yml',
    ).readAsStringSync();
    final readme = File('${repositoryRoot.path}/README.md').readAsStringSync();

    expect(workflow, contains('name: Build GitHub Release'));
    expect(workflow, contains("tags:\n      - 'v*'"));
    expect(workflow, contains('permissions:\n  contents: read'));
    expect(workflow, contains('publish-release:'));
    expect(workflow, contains('contents: write'));
    expect(
      workflow,
      contains(
        'actions/download-artifact@'
        '3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c',
      ),
    );
    expect(workflow, contains('sha256sum --check'));
    expect(workflow, contains('gh release create'));
    expect(workflow, contains('dist/macos/*.dmg'));
    expect(workflow, contains('dist/windows/*-setup.exe'));
    expect(workflow, contains('-release-metadata.zip'));
    expect(workflow, isNot(contains('CLIENT_SECRET')));
    expect(workflow, isNot(contains('github_app_private_key')));

    expect(
      readme,
      contains('https://github.com/geng452654716/google-code/releases/latest'),
    );
    expect(readme, contains('macOS 包使用 ad hoc 签名'));
    expect(readme, contains('Windows 包未使用 Authenticode'));
  });
}
