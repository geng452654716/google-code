import 'account.dart';

/// Decrypted logical contents of the local Vault.
class VaultPayload {
  const VaultPayload({
    required this.schemaVersion,
    required this.accounts,
    required this.groups,
    required this.preferences,
    required this.createdAt,
    required this.updatedAt,
  });

  static const currentSchemaVersion = 1;

  final int schemaVersion;
  final List<Account> accounts;
  final List<Map<String, Object?>> groups;
  final Map<String, Object?> preferences;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory VaultPayload.empty(DateTime now) => VaultPayload(
    schemaVersion: currentSchemaVersion,
    accounts: const [],
    groups: const [],
    preferences: const {'autoLockMinutes': 5},
    createdAt: now.toUtc(),
    updatedAt: now.toUtc(),
  );

  VaultPayload copyWith({
    List<Account>? accounts,
    List<Map<String, Object?>>? groups,
    Map<String, Object?>? preferences,
    DateTime? updatedAt,
  }) => VaultPayload(
    schemaVersion: schemaVersion,
    accounts: accounts ?? this.accounts,
    groups: groups ?? this.groups,
    preferences: preferences ?? this.preferences,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'accounts': accounts.map((account) => account.toJson()).toList(),
    'groups': groups,
    'preferences': preferences,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory VaultPayload.fromJson(Map<String, Object?> json) {
    final schemaVersion = json['schemaVersion'] as int?;
    if (schemaVersion != currentSchemaVersion) {
      throw FormatException('Unsupported payload schema: $schemaVersion.');
    }
    return VaultPayload(
      schemaVersion: schemaVersion!,
      accounts: ((json['accounts'] as List?) ?? const [])
          .map(
            (value) => Account.fromJson((value as Map).cast<String, Object?>()),
          )
          .toList(growable: false),
      groups: ((json['groups'] as List?) ?? const [])
          .map((value) => (value as Map).cast<String, Object?>())
          .toList(growable: false),
      preferences: ((json['preferences'] as Map?) ?? const {})
          .cast<String, Object?>(),
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
    );
  }
}
