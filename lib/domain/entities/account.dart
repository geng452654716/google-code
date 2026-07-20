import '../totp/totp.dart';

/// One authenticator account kept only inside an unlocked Vault payload.
class Account {
  const Account({
    required this.id,
    required this.issuer,
    required this.accountName,
    required this.secret,
    required this.algorithm,
    required this.digits,
    required this.periodSeconds,
    required this.sortOrder,
    required this.isPinned,
    required this.createdAt,
    required this.updatedAt,
    this.groupId,
    this.lastUsedAt,
  });

  final String id;
  final String issuer;
  final String accountName;
  final String secret;
  final TotpAlgorithm algorithm;
  final int digits;
  final int periodSeconds;
  final String? groupId;
  final int sortOrder;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastUsedAt;

  /// Converts the account into the existing TOTP engine configuration.
  TotpConfig toTotpConfig() => TotpConfig(
    secret: secret,
    accountName: accountName,
    issuer: issuer.isEmpty ? null : issuer,
    algorithm: algorithm,
    digits: digits,
    period: periodSeconds,
  );

  Account copyWith({
    String? issuer,
    String? accountName,
    String? secret,
    TotpAlgorithm? algorithm,
    int? digits,
    int? periodSeconds,
    String? groupId,
    bool clearGroup = false,
    int? sortOrder,
    bool? isPinned,
    DateTime? updatedAt,
    DateTime? lastUsedAt,
  }) => Account(
    id: id,
    issuer: issuer ?? this.issuer,
    accountName: accountName ?? this.accountName,
    secret: secret ?? this.secret,
    algorithm: algorithm ?? this.algorithm,
    digits: digits ?? this.digits,
    periodSeconds: periodSeconds ?? this.periodSeconds,
    groupId: clearGroup ? null : groupId ?? this.groupId,
    sortOrder: sortOrder ?? this.sortOrder,
    isPinned: isPinned ?? this.isPinned,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'issuer': issuer,
    'accountName': accountName,
    'secret': secret,
    'algorithm': algorithm.otpAuthName,
    'digits': digits,
    'periodSeconds': periodSeconds,
    'groupId': groupId,
    'sortOrder': sortOrder,
    'isPinned': isPinned,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'lastUsedAt': lastUsedAt?.toUtc().toIso8601String(),
  };

  /// Restores both current schema-v1 accounts and early schema-v1 records that
  /// omitted optional presentation fields. Required identity and secret fields
  /// remain strict so recovery never silently drops or invents an account.
  factory Account.fromJson(
    Map<String, Object?> json, {
    int fallbackSortOrder = 0,
    DateTime? fallbackCreatedAt,
    DateTime? fallbackUpdatedAt,
  }) {
    final createdAt = _dateTimeField(json, 'createdAt') ?? fallbackCreatedAt;
    final updatedAt =
        _dateTimeField(json, 'updatedAt') ?? fallbackUpdatedAt ?? createdAt;
    if (createdAt == null) {
      throw const FormatException('Account field createdAt is missing.');
    }
    if (updatedAt == null) {
      throw const FormatException('Account field updatedAt is missing.');
    }

    final periodSeconds = json.containsKey('periodSeconds')
        ? _intField(json, 'periodSeconds')
        : _intField(json, 'period');
    final algorithmName = _stringField(json, 'algorithm');

    return Account(
      id: _requiredString(json, 'id'),
      issuer: _stringField(json, 'issuer') ?? '',
      accountName: _requiredString(json, 'accountName'),
      secret: _requiredString(json, 'secret'),
      algorithm: TotpAlgorithm.parse(algorithmName),
      digits: _intField(json, 'digits') ?? 6,
      periodSeconds: periodSeconds ?? 30,
      groupId: json['groupId'] is String ? json['groupId']! as String : null,
      sortOrder: _intField(json, 'sortOrder') ?? fallbackSortOrder,
      isPinned: _boolField(json, 'isPinned') ?? false,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastUsedAt: _dateTimeField(json, 'lastUsedAt'),
    );
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = _stringField(json, key);
  if (value == null || value.isEmpty) {
    throw FormatException('Account field $key is missing.');
  }
  return value;
}

String? _stringField(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException('Account field $key has an invalid type.');
}

int? _intField(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw FormatException('Account field $key has an invalid integer value.');
}

bool? _boolField(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is bool) return value;
  if (value is num && value == 1) return true;
  if (value is num && value == 0) return false;
  if (value is String && value.toLowerCase() == 'true') return true;
  if (value is String && value.toLowerCase() == 'false') return false;
  throw FormatException('Account field $key has an invalid boolean value.');
}

DateTime? _dateTimeField(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) {
    final parsed = DateTime.tryParse(value)?.toUtc();
    if (parsed != null) return parsed;
  }
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }
  throw FormatException('Account field $key has an invalid timestamp.');
}
