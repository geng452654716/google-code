import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../data/backup/backup_crypto_service.dart';
import '../../domain/backup/backup.dart';
import '../../domain/entities/account.dart';
import '../../domain/entities/vault_payload.dart';

/// Coordinates encrypted export, restore preview, and deterministic merging.
class BackupService {
  BackupService({
    BackupCryptoService? cryptoService,
    Uuid? uuid,
    DateTime Function()? now,
  }) : _cryptoService = cryptoService ?? BackupCryptoService(),
       _uuid = uuid ?? const Uuid(),
       _now = now ?? (() => DateTime.now().toUtc());

  final BackupCryptoService _cryptoService;
  final Uuid _uuid;
  final DateTime Function() _now;

  /// Creates encrypted backup bytes without writing an intermediate clear file.
  Future<Uint8List> export(VaultPayload payload, String password) {
    return _cryptoService.create(payload, password, createdAt: _now());
  }

  /// Decrypts the backup and calculates only aggregate conflict information.
  Future<BackupRestorePreview> preview(
    Uint8List bytes,
    String password,
    VaultPayload current,
  ) async {
    final opened = await _cryptoService.open(bytes, password);
    var exactDuplicates = 0;
    var conflicts = 0;
    for (final candidate in opened.payload.accounts) {
      if (current.accounts.any(
        (account) => _isExactDuplicate(account, candidate),
      )) {
        exactDuplicates += 1;
      } else if (current.accounts.any(
        (account) => _hasSameLabel(account, candidate),
      )) {
        conflicts += 1;
      }
    }
    return BackupRestorePreview(
      backupCreatedAt: opened.createdAt,
      payload: opened.payload,
      summary: BackupRestoreSummary(
        accountCount: opened.payload.accounts.length,
        groupCount: opened.payload.groups.length,
        newAccountCount: opened.payload.accounts.length - exactDuplicates,
        exactDuplicateCount: exactDuplicates,
        conflictCount: conflicts,
      ),
    );
  }

  /// Builds the final payload while leaving persistence to the session controller.
  BackupRestoreResult prepareRestore({
    required VaultPayload current,
    required BackupRestorePreview preview,
    required BackupRestoreMode mode,
  }) {
    if (mode == BackupRestoreMode.replace) {
      final replacement = VaultPayload(
        schemaVersion: preview.payload.schemaVersion,
        accounts: List.unmodifiable(preview.payload.accounts),
        groups: List.unmodifiable(preview.payload.groups),
        preferences: Map.unmodifiable(preview.payload.preferences),
        createdAt: preview.payload.createdAt,
        updatedAt: _now(),
      );
      return BackupRestoreResult(
        payload: replacement,
        mode: mode,
        addedAccountCount: replacement.accounts.length,
        skippedDuplicateCount: 0,
        conflictCount: preview.summary.conflictCount,
      );
    }

    final groups = current.groups.map(Map<String, Object?>.from).toList();
    final groupIdRemap = <String, String>{};
    final existingGroupIds = <String>{
      for (final group in groups)
        if (group['id'] case final String id) id,
    };
    for (final backupGroup in preview.payload.groups) {
      final candidate = Map<String, Object?>.from(backupGroup);
      final id = candidate['id'];
      if (id is! String) {
        if (!groups.any((group) => _deepEquals(group, candidate))) {
          groups.add(candidate);
        }
        continue;
      }
      final sameId = groups.where((group) => group['id'] == id);
      if (sameId.any((group) => _deepEquals(group, candidate))) {
        continue;
      }
      if (!existingGroupIds.contains(id)) {
        groups.add(candidate);
        existingGroupIds.add(id);
        continue;
      }
      final replacementId = _uuid.v4();
      candidate['id'] = replacementId;
      groupIdRemap[id] = replacementId;
      groups.add(candidate);
      existingGroupIds.add(replacementId);
    }

    final accounts = current.accounts.toList();
    final existingIds = accounts.map((account) => account.id).toSet();
    final sortedCandidates = preview.payload.accounts.toList()
      ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
    var nextSortOrder = accounts.fold<int>(
      0,
      (highest, account) =>
          account.sortOrder >= highest ? account.sortOrder + 1 : highest,
    );
    var skippedDuplicates = 0;
    var conflicts = 0;
    var added = 0;

    for (final candidate in sortedCandidates) {
      if (accounts.any((account) => _isExactDuplicate(account, candidate))) {
        skippedDuplicates += 1;
        continue;
      }
      if (accounts.any((account) => _hasSameLabel(account, candidate))) {
        conflicts += 1;
      }
      var id = candidate.id;
      if (existingIds.contains(id)) id = _uuid.v4();
      existingIds.add(id);
      accounts.add(
        Account(
          id: id,
          issuer: candidate.issuer,
          accountName: candidate.accountName,
          secret: candidate.secret,
          algorithm: candidate.algorithm,
          digits: candidate.digits,
          periodSeconds: candidate.periodSeconds,
          groupId: candidate.groupId == null
              ? null
              : groupIdRemap[candidate.groupId] ?? candidate.groupId,
          sortOrder: nextSortOrder++,
          isPinned: candidate.isPinned,
          createdAt: candidate.createdAt,
          updatedAt: candidate.updatedAt,
          lastUsedAt: candidate.lastUsedAt,
        ),
      );
      added += 1;
    }

    return BackupRestoreResult(
      payload: VaultPayload(
        schemaVersion: current.schemaVersion,
        accounts: List.unmodifiable(accounts),
        groups: List.unmodifiable(groups),
        preferences: Map.unmodifiable(current.preferences),
        createdAt: current.createdAt,
        updatedAt: _now(),
      ),
      mode: mode,
      addedAccountCount: added,
      skippedDuplicateCount: skippedDuplicates,
      conflictCount: conflicts,
    );
  }

  bool _isExactDuplicate(Account left, Account right) =>
      _hasSameLabel(left, right) && left.secret == right.secret;

  bool _hasSameLabel(Account left, Account right) =>
      left.issuer.trim().toLowerCase() == right.issuer.trim().toLowerCase() &&
      left.accountName.trim().toLowerCase() ==
          right.accountName.trim().toLowerCase();

  bool _deepEquals(Object? left, Object? right) =>
      jsonEncode(left) == jsonEncode(right);
}
