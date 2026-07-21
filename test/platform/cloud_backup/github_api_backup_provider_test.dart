import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/platform/cloud_backup/cloud_backup_provider.dart';
import 'package:google_code/platform/cloud_backup/github_api_backup_provider.dart';
import 'package:google_code/platform/security/device_secret_store.dart';

void main() {
  final now = DateTime.utc(2026, 7, 21, 10);

  test('rejects authorization when client ID is not configured', () async {
    final provider = GitHubApiBackupProvider(
      secretStore: _MemorySecretStore(),
      clientId: '',
      transport: _FakeTransport(),
      now: () => now,
    );

    expect(provider.isConfigured, isFalse);
    await expectLater(
      provider.startAuthorization(),
      throwsA(
        isA<CloudBackupException>().having(
          (error) => error.message,
          'message',
          contains('Client ID'),
        ),
      ),
    );
  });

  test(
    'parses device code, waits through pending, and stores session',
    () async {
      final store = _MemorySecretStore();
      final transport = _FakeTransport([
        _response(200, {
          'device_code': 'device-token',
          'user_code': 'ABCD-EFGH',
          'verification_uri': 'https://github.com/login/device',
          'expires_in': 900,
          'interval': 3,
        }),
        _response(200, {'error': 'authorization_pending'}),
        _response(200, {'error': 'slow_down'}),
        _response(200, {
          'access_token': 'access-token',
          'refresh_token': 'refresh-token',
          'expires_in': 28800,
          'refresh_token_expires_in': 15897600,
        }),
      ]);
      final delays = <Duration>[];
      final provider = GitHubApiBackupProvider(
        secretStore: store,
        clientId: 'Iv-test',
        transport: transport,
        delay: (duration) async => delays.add(duration),
        now: () => now,
      );

      final code = await provider.startAuthorization();
      await provider.finishAuthorization(code);

      expect(code.userCode, 'ABCD-EFGH');
      expect(code.verificationUri.host, 'github.com');
      expect(delays, [
        const Duration(seconds: 3),
        const Duration(seconds: 3),
        const Duration(seconds: 8),
      ]);
      expect((await provider.connectionState()).isConnected, isTrue);
      expect(store.values['cloud.github.session.v1'], isNotNull);
      expect(
        utf8.decode(store.values['cloud.github.session.v1']!),
        allOf(contains('access-token'), contains('refresh-token')),
      );
    },
  );

  test(
    'cancellation prevents a completed device flow from being stored',
    () async {
      final cancellation = GitHubAuthorizationCancellation();
      final store = _MemorySecretStore();
      final provider = GitHubApiBackupProvider(
        secretStore: store,
        clientId: 'Iv-test',
        transport: _FakeTransport([
          _response(200, {'access_token': 'must-not-be-saved'}),
        ]),
        delay: (_) async => cancellation.cancel(),
        now: () => now,
      );
      final code = GitHubDeviceCode(
        deviceCode: 'device',
        userCode: 'CODE',
        verificationUri: Uri.parse('https://github.com/login/device'),
        expiresAt: now.add(const Duration(minutes: 5)),
        interval: const Duration(seconds: 1),
      );

      await expectLater(
        provider.finishAuthorization(code, cancellation: cancellation),
        throwsA(isA<CloudBackupException>()),
      );
      expect(store.values, isEmpty);
    },
  );

  test('lists only writable private repositories and selects one', () async {
    final fixture = await _authorizedProvider(now: now);
    fixture.transport.responses.addAll([
      _response(200, {
        'installations': [
          {
            'id': 42,
            'permissions': {'contents': 'write'},
          },
          {
            'id': 43,
            'permissions': {'contents': 'read'},
          },
        ],
      }),
      _response(200, {
        'repositories': [
          {'id': 2, 'full_name': 'owner/public', 'private': false},
          {'id': 1, 'full_name': 'owner/private-backup', 'private': true},
        ],
      }),
    ]);

    final repositories = await fixture.provider.listRepositories();
    await fixture.provider.selectRepository(repositories.single);

    expect(repositories.map((repo) => repo.fullName), ['owner/private-backup']);
    expect(
      (await fixture.provider.connectionState()).repository,
      'owner/private-backup',
    );
    expect(
      fixture.transport.requests.map((request) => request.uri.path),
      contains('/user/installations/42/repositories'),
    );
  });

  test(
    'uploads a new backup and includes existing sha when updating',
    () async {
      final fixture = await _authorizedProvider(
        now: now,
        repository: 'owner/private-backup',
      );
      fixture.transport.responses.addAll([
        _response(200, {'sha': 'existing-sha'}),
        _response(200, {'content': {}}),
      ]);

      final result = await fixture.provider.upload(
        Uint8List.fromList([1, 2, 3]),
        suggestedName: 'ignored.gcbak',
      );

      expect(result?.destination, 'owner/private-backup');
      final put = fixture.transport.requests.last;
      expect(put.method, 'PUT');
      expect(put.jsonBody?['sha'], 'existing-sha');
      expect(put.jsonBody?['content'], base64Encode([1, 2, 3]));
      expect(put.jsonBody?['message'], isNot(contains('owner/private-backup')));
    },
  );

  test('downloads and decodes the latest encrypted backup', () async {
    final fixture = await _authorizedProvider(
      now: now,
      repository: 'owner/private-backup',
    );
    fixture.transport.responses.add(
      _response(200, {
        'encoding': 'base64',
        'content': base64Encode([4, 5, 6]),
      }),
    );

    final backup = await fixture.provider.downloadLatest();

    expect(backup?.bytes, [4, 5, 6]);
    expect(backup?.name, contains('owner/private-backup'));
  });

  test('refreshes an expiring token before an authorized request', () async {
    final store = _MemorySecretStore();
    store.seedSession({
      'accessToken': 'expired-access',
      'refreshToken': 'refresh-token',
      'accessTokenExpiresAt': now
          .add(const Duration(minutes: 1))
          .toIso8601String(),
      'refreshTokenExpiresAt': now
          .add(const Duration(days: 1))
          .toIso8601String(),
    });
    final transport = _FakeTransport([
      _response(200, {
        'access_token': 'refreshed-access',
        'refresh_token': 'next-refresh',
        'expires_in': 28800,
        'refresh_token_expires_in': 15897600,
      }),
      _response(200, {'installations': []}),
    ]);
    final provider = GitHubApiBackupProvider(
      secretStore: store,
      clientId: 'Iv-test',
      transport: transport,
      now: () => now,
    );

    await provider.listRepositories();

    expect(transport.requests.first.formBody?['grant_type'], 'refresh_token');
    expect(transport.requests.last.bearerToken, 'refreshed-access');
  });

  test('deletes the stored session after an unauthorized response', () async {
    final fixture = await _authorizedProvider(
      now: now,
      repository: 'owner/private-backup',
    );
    fixture.transport.responses.add(
      _response(401, {'message': 'Bad credentials'}),
    );

    await expectLater(
      fixture.provider.downloadLatest(),
      throwsA(
        isA<CloudBackupException>().having(
          (error) => error.message,
          'message',
          contains('重新连接'),
        ),
      ),
    );
    expect(fixture.store.values, isEmpty);
  });
}

GitHubHttpResponse _response(int statusCode, Map<String, Object?> body) =>
    GitHubHttpResponse(statusCode: statusCode, body: body);

Future<_ProviderFixture> _authorizedProvider({
  required DateTime now,
  String? repository,
}) async {
  final store = _MemorySecretStore();
  final session = <String, Object?>{'accessToken': 'access-token'};
  if (repository != null) session['repository'] = repository;
  store.seedSession(session);
  final transport = _FakeTransport();
  return _ProviderFixture(
    store: store,
    transport: transport,
    provider: GitHubApiBackupProvider(
      secretStore: store,
      clientId: 'Iv-test',
      transport: transport,
      now: () => now,
    ),
  );
}

class _ProviderFixture {
  const _ProviderFixture({
    required this.store,
    required this.transport,
    required this.provider,
  });

  final _MemorySecretStore store;
  final _FakeTransport transport;
  final GitHubApiBackupProvider provider;
}

class _MemorySecretStore implements DeviceSecretStore {
  final values = <String, Uint8List>{};

  void seedSession(Map<String, Object?> json) {
    values['cloud.github.session.v1'] = Uint8List.fromList(
      utf8.encode(jsonEncode(json)),
    );
  }

  @override
  Future<void> delete(String key) async {
    final removed = values.remove(key);
    removed?.fillRange(0, removed.length, 0);
  }

  @override
  Future<Uint8List?> read(String key) async {
    final value = values[key];
    return value == null ? null : Uint8List.fromList(value);
  }

  @override
  Future<void> write(String key, Uint8List value) async {
    values[key] = Uint8List.fromList(value);
  }
}

class _FakeTransport implements GitHubHttpTransport {
  _FakeTransport([List<GitHubHttpResponse>? responses])
    : responses = responses ?? <GitHubHttpResponse>[];

  final List<GitHubHttpResponse> responses;
  final requests = <_RecordedRequest>[];

  @override
  Future<GitHubHttpResponse> request(
    String method,
    Uri uri, {
    required bool githubApiHeaders,
    Map<String, String>? formBody,
    Map<String, Object?>? jsonBody,
    String? bearerToken,
  }) async {
    requests.add(
      _RecordedRequest(
        method: method,
        uri: uri,
        formBody: formBody,
        jsonBody: jsonBody,
        bearerToken: bearerToken,
      ),
    );
    if (responses.isEmpty) {
      throw StateError('No fake response for $method $uri');
    }
    return responses.removeAt(0);
  }
}

class _RecordedRequest {
  const _RecordedRequest({
    required this.method,
    required this.uri,
    this.formBody,
    this.jsonBody,
    this.bearerToken,
  });

  final String method;
  final Uri uri;
  final Map<String, String>? formBody;
  final Map<String, Object?>? jsonBody;
  final String? bearerToken;
}
