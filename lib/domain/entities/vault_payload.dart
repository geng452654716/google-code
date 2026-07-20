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
  static final _legacyTimestamp = DateTime.fromMillisecondsSinceEpoch(
    0,
    isUtc: true,
  );

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
    final schemaVersion = _intField(json, 'schemaVersion') ?? 1;
    if (schemaVersion != currentSchemaVersion) {
      throw FormatException('Unsupported payload schema: $schemaVersion.');
    }

    final createdAt = _dateTimeField(json, 'createdAt') ?? _legacyTimestamp;
    final updatedAt = _dateTimeField(json, 'updatedAt') ?? createdAt;
    final groups = _parseGroups(json['groups']);
    final knownGroupIds = groups
        .map((group) => group['id'])
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    final rawAccounts = json['accounts'];
    if (rawAccounts != null && rawAccounts is! List) {
      throw const FormatException('Vault field accounts must be a list.');
    }

    final accounts = <Account>[];
    for (final (index, value) in (rawAccounts as List? ?? const []).indexed) {
      if (value is! Map) {
        throw FormatException(
          'Vault field accounts[$index] must be an object.',
        );
      }
      try {
        final account = Account.fromJson(
          value.cast<String, Object?>(),
          fallbackSortOrder: index,
          fallbackCreatedAt: createdAt,
          fallbackUpdatedAt: updatedAt,
        );
        accounts.add(
          account.groupId != null && !knownGroupIds.contains(account.groupId)
              ? account.copyWith(clearGroup: true)
              : account,
        );
      } on FormatException catch (error) {
        throw FormatException(
          'Vault field accounts[$index] is incompatible: ${error.message}',
        );
      } on Object {
        throw FormatException('Vault field accounts[$index] is incompatible.');
      }
    }

    final rawPreferences = json['preferences'];
    if (rawPreferences != null && rawPreferences is! Map) {
      throw const FormatException('Vault field preferences must be an object.');
    }

    return VaultPayload(
      schemaVersion: schemaVersion,
      accounts: List.unmodifiable(accounts),
      groups: groups,
      preferences: Map.unmodifiable(
        (rawPreferences as Map? ?? const {}).cast<String, Object?>(),
      ),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static List<Map<String, Object?>> _parseGroups(Object? value) {
    if (value == null) return const [];
    if (value is! List) {
      throw const FormatException('Vault field groups must be a list.');
    }
    final groups = <Map<String, Object?>>[];
    for (final (index, group) in value.indexed) {
      if (group is! Map) {
        throw FormatException('Vault field groups[$index] must be an object.');
      }
      groups.add(Map.unmodifiable(group.cast<String, Object?>()));
    }
    return List.unmodifiable(groups);
  }
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
  throw FormatException('Vault field $key has an invalid integer value.');
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
  throw FormatException('Vault field $key has an invalid timestamp.');
}
