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

  factory Account.fromJson(Map<String, Object?> json) => Account(
    id: json['id'] as String,
    issuer: json['issuer'] as String? ?? '',
    accountName: json['accountName'] as String,
    secret: json['secret'] as String,
    algorithm: TotpAlgorithm.parse(json['algorithm'] as String?),
    digits: json['digits'] as int,
    periodSeconds: json['periodSeconds'] as int,
    groupId: json['groupId'] as String?,
    sortOrder: json['sortOrder'] as int? ?? 0,
    isPinned: json['isPinned'] as bool? ?? false,
    createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
    updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
    lastUsedAt: json['lastUsedAt'] == null
        ? null
        : DateTime.parse(json['lastUsedAt'] as String).toUtc(),
  );
}
