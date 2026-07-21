import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../data/backup/backup_crypto_service.dart';
import '../files/backup_file_service.dart';
import '../security/device_secret_store.dart';
import 'cloud_backup_provider.dart';

class GitHubDeviceCode {
  const GitHubDeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresAt,
    required this.interval,
  });

  final String deviceCode;
  final String userCode;
  final Uri verificationUri;
  final DateTime expiresAt;
  final Duration interval;
}

class GitHubBackupRepository {
  const GitHubBackupRepository({
    required this.id,
    required this.fullName,
    required this.isPrivate,
  });

  final int id;
  final String fullName;
  final bool isPrivate;
}

class GitHubAuthorizationCancellation {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() => _isCancelled = true;
}

class GitHubConnectionState {
  const GitHubConnectionState({required this.isConnected, this.repository});

  final bool isConnected;
  final String? repository;
}

abstract interface class GitHubCloudBackupProvider
    implements CloudBackupProvider {
  bool get isConfigured;

  Future<GitHubConnectionState> connectionState();

  Future<GitHubDeviceCode> startAuthorization();

  Future<void> finishAuthorization(
    GitHubDeviceCode code, {
    GitHubAuthorizationCancellation? cancellation,
  });

  Future<List<GitHubBackupRepository>> listRepositories();

  Future<void> selectRepository(GitHubBackupRepository repository);

  Future<void> disconnect();
}

class GitHubHttpResponse {
  const GitHubHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final Map<String, Object?> body;
}

abstract interface class GitHubHttpTransport {
  Future<GitHubHttpResponse> request(
    String method,
    Uri uri, {
    required bool githubApiHeaders,
    Map<String, String>? formBody,
    Map<String, Object?>? jsonBody,
    String? bearerToken,
  });
}

/// Small transport wrapper kept separate so authorization behavior can be tested
/// without making real GitHub requests.
class HttpClientGitHubTransport implements GitHubHttpTransport {
  HttpClientGitHubTransport({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;

  static const _apiVersion = '2026-03-10';
  final HttpClient Function() _clientFactory;

  @override
  Future<GitHubHttpResponse> request(
    String method,
    Uri uri, {
    required bool githubApiHeaders,
    Map<String, String>? formBody,
    Map<String, Object?>? jsonBody,
    String? bearerToken,
  }) async {
    final client = _clientFactory();
    try {
      final request = await client
          .openUrl(method, uri)
          .timeout(const Duration(seconds: 20));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (githubApiHeaders) {
        request.headers.set('X-GitHub-Api-Version', _apiVersion);
        request.headers.set(HttpHeaders.userAgentHeader, 'TOTP-Vault');
      }
      if (bearerToken != null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $bearerToken',
        );
      }
      if (jsonBody != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(jsonBody));
      } else if (formBody != null) {
        request.headers.contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
        );
        request.write(
          formBody.entries
              .map(
                (entry) =>
                    '${Uri.encodeQueryComponent(entry.key)}='
                    '${Uri.encodeQueryComponent(entry.value)}',
              )
              .join('&'),
        );
      }
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final text = await utf8.decoder.bind(response).join();
      final decoded = text.isEmpty ? <String, Object?>{} : jsonDecode(text);
      return GitHubHttpResponse(
        statusCode: response.statusCode,
        body: decoded is Map
            ? decoded.cast<String, Object?>()
            : const <String, Object?>{},
      );
    } on CloudBackupException {
      rethrow;
    } on Object {
      throw const CloudBackupException('无法连接 GitHub，请检查网络后重试。');
    } finally {
      client.close(force: true);
    }
  }
}

typedef Delay = Future<void> Function(Duration duration);

/// GitHub App Device Flow provider using only app-authorized private repositories.
class GitHubApiBackupProvider implements GitHubCloudBackupProvider {
  GitHubApiBackupProvider({
    required this.secretStore,
    String? clientId,
    GitHubHttpTransport? transport,
    Delay? delay,
    DateTime Function()? now,
  }) : clientId = clientId ?? const String.fromEnvironment(_clientIdDefine),
       _transport = transport ?? HttpClientGitHubTransport(),
       _delay = delay ?? Future<void>.delayed,
       _now = now ?? (() => DateTime.now().toUtc());

  static const _clientIdDefine = 'TOTP_VAULT_GITHUB_CLIENT_ID';
  static const _secretKey = 'cloud.github.session.v1';
  static const _backupPath = 'totp-vault-backup/latest.gcbak';
  static final _repositoryPattern = RegExp(
    r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$',
  );

  final DeviceSecretStore secretStore;
  final String clientId;
  final GitHubHttpTransport _transport;
  final Delay _delay;
  final DateTime Function() _now;

  @override
  bool get isConfigured => clientId.trim().isNotEmpty;

  @override
  CloudBackupProviderInfo get info => const CloudBackupProviderInfo(
    type: CloudBackupProviderType.github,
    title: 'GitHub',
    description: '登录任意 GitHub 账号，并选择 App 已获授权的专用私有仓库',
    iconName: 'code',
  );

  @override
  Future<GitHubConnectionState> connectionState() async {
    if (!isConfigured) {
      return const GitHubConnectionState(isConnected: false);
    }
    final session = await _readSession();
    return GitHubConnectionState(
      isConnected: session != null,
      repository: session?.repository,
    );
  }

  @override
  Future<GitHubDeviceCode> startAuthorization() async {
    _requireConfigured();
    final response = await _requestJson(
      'POST',
      Uri.parse('https://github.com/login/device/code'),
      formBody: {'client_id': clientId},
      githubApiHeaders: false,
    );
    final deviceCode = response['device_code'];
    final userCode = response['user_code'];
    final verificationUri = response['verification_uri'];
    final expiresIn = response['expires_in'];
    final interval = response['interval'];
    if (deviceCode is! String ||
        userCode is! String ||
        verificationUri is! String ||
        expiresIn is! num) {
      throw const CloudBackupException('GitHub 没有返回有效的授权码。');
    }
    final uri = Uri.tryParse(verificationUri);
    if (uri == null || uri.scheme != 'https' || uri.host != 'github.com') {
      throw const CloudBackupException('GitHub 返回了无效的授权地址。');
    }
    return GitHubDeviceCode(
      deviceCode: deviceCode,
      userCode: userCode,
      verificationUri: uri,
      expiresAt: _now().add(Duration(seconds: expiresIn.toInt())),
      interval: Duration(seconds: interval is num ? interval.toInt() : 5),
    );
  }

  @override
  Future<void> finishAuthorization(
    GitHubDeviceCode code, {
    GitHubAuthorizationCancellation? cancellation,
  }) async {
    var interval = code.interval;
    while (_now().isBefore(code.expiresAt)) {
      if (cancellation?.isCancelled ?? false) {
        throw const CloudBackupException('GitHub 授权已取消。');
      }
      await _delay(interval);
      if (cancellation?.isCancelled ?? false) {
        throw const CloudBackupException('GitHub 授权已取消。');
      }
      final response = await _requestJson(
        'POST',
        Uri.parse('https://github.com/login/oauth/access_token'),
        formBody: {
          'client_id': clientId,
          'device_code': code.deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        },
        githubApiHeaders: false,
        allowOAuthError: true,
      );
      final accessToken = response['access_token'];
      if (accessToken is String && accessToken.isNotEmpty) {
        if (cancellation?.isCancelled ?? false) {
          throw const CloudBackupException('GitHub 授权已取消。');
        }
        final expiresIn = response['expires_in'];
        final refreshExpiresIn = response['refresh_token_expires_in'];
        await _writeSession(
          _GitHubSession(
            accessToken: accessToken,
            refreshToken: response['refresh_token'] as String?,
            accessTokenExpiresAt: expiresIn is num
                ? _now().add(Duration(seconds: expiresIn.toInt()))
                : null,
            refreshTokenExpiresAt: refreshExpiresIn is num
                ? _now().add(Duration(seconds: refreshExpiresIn.toInt()))
                : null,
          ),
        );
        return;
      }
      switch (response['error']) {
        case 'authorization_pending':
          continue;
        case 'slow_down':
          interval += const Duration(seconds: 5);
          continue;
        case 'access_denied':
          throw const CloudBackupException('GitHub 授权已被取消。');
        case 'expired_token':
          throw const CloudBackupException('GitHub 授权码已过期，请重新连接。');
        default:
          throw const CloudBackupException('GitHub 授权失败，请稍后重试。');
      }
    }
    throw const CloudBackupException('GitHub 授权码已过期，请重新连接。');
  }

  @override
  Future<List<GitHubBackupRepository>> listRepositories() async {
    final session = await _requireSession();
    final installations = await _authorizedJson(
      session,
      'GET',
      Uri.parse('https://api.github.com/user/installations?per_page=100'),
    );
    final rawInstallations = installations['installations'];
    if (rawInstallations is! List) return const [];

    final repositories = <GitHubBackupRepository>[];
    for (final installation in rawInstallations.whereType<Map>()) {
      final id = installation['id'];
      final permissions = installation['permissions'];
      if (id is! num || permissions is! Map) continue;
      if (permissions['contents'] != 'write') continue;

      final page = await _authorizedJson(
        session,
        'GET',
        Uri.parse(
          'https://api.github.com/user/installations/${id.toInt()}/repositories?per_page=100',
        ),
      );
      final values = page['repositories'];
      if (values is! List) continue;
      for (final value in values.whereType<Map>()) {
        final repoId = value['id'];
        final fullName = value['full_name'];
        final isPrivate = value['private'] == true;
        if (repoId is num &&
            fullName is String &&
            isPrivate &&
            _repositoryPattern.hasMatch(fullName)) {
          repositories.add(
            GitHubBackupRepository(
              id: repoId.toInt(),
              fullName: fullName,
              isPrivate: true,
            ),
          );
        }
      }
    }
    repositories.sort((left, right) => left.fullName.compareTo(right.fullName));
    return repositories;
  }

  @override
  Future<void> selectRepository(GitHubBackupRepository repository) async {
    if (!repository.isPrivate ||
        !_repositoryPattern.hasMatch(repository.fullName)) {
      throw const CloudBackupException('云备份只能使用 GitHub 私有仓库。');
    }
    final session = await _requireSession();
    await _writeSession(session.withRepository(repository.fullName));
  }

  @override
  Future<void> disconnect() => secretStore.delete(_secretKey);

  @override
  Future<CloudBackupUploadResult?> upload(
    Uint8List encryptedBackup, {
    required String suggestedName,
  }) async {
    if (encryptedBackup.isEmpty ||
        encryptedBackup.length > BackupCryptoService.maxBackupBytes) {
      throw const CloudBackupException('加密备份超过 32 MiB 限制。');
    }
    final session = await _requireSession(requireRepository: true);
    final repository = session.repository!;
    final current = await _authorizedJson(
      session,
      'GET',
      _contentsUri(repository),
      acceptedStatusCodes: const {200, 404},
    );
    final sha = current['sha'];
    await _authorizedJson(
      session,
      'PUT',
      _contentsUri(repository),
      jsonBody: <String, Object?>{
        'message': '更新 TOTP Vault 加密备份',
        'content': base64Encode(encryptedBackup),
        if (sha is String) 'sha': sha,
      },
      acceptedStatusCodes: const {200, 201},
    );
    return CloudBackupUploadResult(
      provider: info.type,
      destination: repository,
      createdAt: _now(),
    );
  }

  @override
  Future<PickedBackupFile?> downloadLatest() async {
    final session = await _requireSession(requireRepository: true);
    final response = await _authorizedJson(
      session,
      'GET',
      _contentsUri(session.repository!),
      acceptedStatusCodes: const {200, 404},
    );
    if (response.isEmpty) {
      throw const CloudBackupException('所选 GitHub 仓库中没有云备份。');
    }
    final content = response['content'];
    if (content is! String || response['encoding'] != 'base64') {
      throw const CloudBackupException('GitHub 备份内容无法读取。');
    }
    late final Uint8List bytes;
    try {
      bytes = base64Decode(content.replaceAll(RegExp(r'\s'), ''));
    } on FormatException {
      throw const CloudBackupException('GitHub 备份内容已损坏。');
    }
    if (bytes.length > BackupCryptoService.maxBackupBytes) {
      bytes.fillRange(0, bytes.length, 0);
      throw const CloudBackupException('GitHub 备份超过 32 MiB 限制。');
    }
    return PickedBackupFile(
      bytes: bytes,
      name: 'GitHub / ${session.repository} / latest.gcbak',
    );
  }

  Uri _contentsUri(String repository) => Uri.parse(
    'https://api.github.com/repos/$repository/contents/$_backupPath',
  );

  Future<Map<String, Object?>> _authorizedJson(
    _GitHubSession session,
    String method,
    Uri uri, {
    Map<String, Object?>? jsonBody,
    Set<int> acceptedStatusCodes = const {200},
  }) async {
    final current = await _refreshIfNeeded(session);
    try {
      return await _requestJson(
        method,
        uri,
        bearerToken: current.accessToken,
        jsonBody: jsonBody,
        acceptedStatusCodes: acceptedStatusCodes,
      );
    } on _GitHubAuthorizationException {
      await disconnect();
      throw const CloudBackupException('GitHub 授权已失效，请重新连接。');
    }
  }

  Future<_GitHubSession> _refreshIfNeeded(_GitHubSession session) async {
    final expiresAt = session.accessTokenExpiresAt;
    if (expiresAt == null ||
        expiresAt.isAfter(_now().add(const Duration(minutes: 2)))) {
      return session;
    }
    final refreshToken = session.refreshToken;
    if (refreshToken == null ||
        (session.refreshTokenExpiresAt?.isBefore(_now()) ?? false)) {
      await disconnect();
      throw const CloudBackupException('GitHub 授权已过期，请重新连接。');
    }
    final response = await _requestJson(
      'POST',
      Uri.parse('https://github.com/login/oauth/access_token'),
      formBody: {
        'client_id': clientId,
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      },
      githubApiHeaders: false,
    );
    final accessToken = response['access_token'];
    if (accessToken is! String || accessToken.isEmpty) {
      await disconnect();
      throw const CloudBackupException('GitHub 授权刷新失败，请重新连接。');
    }
    final expiresIn = response['expires_in'];
    final refreshExpiresIn = response['refresh_token_expires_in'];
    final refreshed = _GitHubSession(
      accessToken: accessToken,
      refreshToken: response['refresh_token'] as String? ?? refreshToken,
      accessTokenExpiresAt: expiresIn is num
          ? _now().add(Duration(seconds: expiresIn.toInt()))
          : null,
      refreshTokenExpiresAt: refreshExpiresIn is num
          ? _now().add(Duration(seconds: refreshExpiresIn.toInt()))
          : session.refreshTokenExpiresAt,
      repository: session.repository,
    );
    await _writeSession(refreshed);
    return refreshed;
  }

  Future<Map<String, Object?>> _requestJson(
    String method,
    Uri uri, {
    Map<String, String>? formBody,
    Map<String, Object?>? jsonBody,
    String? bearerToken,
    bool githubApiHeaders = true,
    bool allowOAuthError = false,
    Set<int> acceptedStatusCodes = const {200},
  }) async {
    final response = await _transport.request(
      method,
      uri,
      githubApiHeaders: githubApiHeaders,
      formBody: formBody,
      jsonBody: jsonBody,
      bearerToken: bearerToken,
    );
    if (acceptedStatusCodes.contains(response.statusCode)) {
      return response.body;
    }
    if (allowOAuthError && response.body['error'] is String) {
      return response.body;
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const _GitHubAuthorizationException();
    }
    throw const CloudBackupException('GitHub 服务暂时无法完成云备份操作。');
  }

  void _requireConfigured() {
    if (!isConfigured) {
      throw const CloudBackupException(
        '当前安装包尚未配置 GitHub App Client ID。请使用配置后的安装包。',
      );
    }
  }

  Future<_GitHubSession> _requireSession({
    bool requireRepository = false,
  }) async {
    _requireConfigured();
    final session = await _readSession();
    if (session == null) {
      throw const CloudBackupException('请先授权连接 GitHub。');
    }
    if (requireRepository && session.repository == null) {
      throw const CloudBackupException('请先选择用于云备份的 GitHub 私有仓库。');
    }
    return session;
  }

  Future<_GitHubSession?> _readSession() async {
    final bytes = await secretStore.read(_secretKey);
    if (bytes == null) return null;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) return null;
      return _GitHubSession.fromJson(decoded.cast<String, Object?>());
    } on Object {
      await secretStore.delete(_secretKey);
      return null;
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<void> _writeSession(_GitHubSession session) async {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(session.toJson())));
    try {
      await secretStore.write(_secretKey, bytes);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }
}

class _GitHubAuthorizationException implements Exception {
  const _GitHubAuthorizationException();
}

class _GitHubSession {
  const _GitHubSession({
    required this.accessToken,
    this.refreshToken,
    this.accessTokenExpiresAt,
    this.refreshTokenExpiresAt,
    this.repository,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime? accessTokenExpiresAt;
  final DateTime? refreshTokenExpiresAt;
  final String? repository;

  _GitHubSession withRepository(String value) => _GitHubSession(
    accessToken: accessToken,
    refreshToken: refreshToken,
    accessTokenExpiresAt: accessTokenExpiresAt,
    refreshTokenExpiresAt: refreshTokenExpiresAt,
    repository: value,
  );

  Map<String, Object?> toJson() => {
    'accessToken': accessToken,
    if (refreshToken != null) 'refreshToken': refreshToken,
    if (accessTokenExpiresAt != null)
      'accessTokenExpiresAt': accessTokenExpiresAt!.toUtc().toIso8601String(),
    if (refreshTokenExpiresAt != null)
      'refreshTokenExpiresAt': refreshTokenExpiresAt!.toUtc().toIso8601String(),
    if (repository != null) 'repository': repository,
  };

  factory _GitHubSession.fromJson(Map<String, Object?> json) {
    final accessToken = json['accessToken'];
    if (accessToken is! String || accessToken.isEmpty) {
      throw const FormatException('Invalid GitHub session.');
    }
    DateTime? date(String key) => json[key] is String
        ? DateTime.tryParse(json[key]! as String)?.toUtc()
        : null;
    final repository = json['repository'];
    if (repository != null &&
        (repository is! String ||
            !GitHubApiBackupProvider._repositoryPattern.hasMatch(repository))) {
      throw const FormatException('Invalid GitHub repository.');
    }
    return _GitHubSession(
      accessToken: accessToken,
      refreshToken: json['refreshToken'] as String?,
      accessTokenExpiresAt: date('accessTokenExpiresAt'),
      refreshTokenExpiresAt: date('refreshTokenExpiresAt'),
      repository: repository as String?,
    );
  }
}
