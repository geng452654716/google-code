import 'dart:typed_data';

import '../files/backup_file_service.dart';

/// Cloud-like destinations supported without exposing backup plaintext.
enum CloudBackupProviderType { iCloudDrive, googleDrive, github }

/// User-facing metadata for one encrypted cloud backup destination.
class CloudBackupProviderInfo {
  const CloudBackupProviderInfo({
    required this.type,
    required this.title,
    required this.description,
    required this.iconName,
  });

  final CloudBackupProviderType type;
  final String title;
  final String description;
  final String iconName;
}

/// Successful upload metadata safe to display and persist in UI state.
class CloudBackupUploadResult {
  const CloudBackupUploadResult({
    required this.provider,
    required this.destination,
    required this.createdAt,
  });

  final CloudBackupProviderType provider;
  final String destination;
  final DateTime createdAt;
}

/// A provider transports only already-encrypted `.gcbak` bytes.
abstract interface class CloudBackupProvider {
  CloudBackupProviderInfo get info;

  /// Lets the user choose/configure a destination and uploads encrypted bytes.
  Future<CloudBackupUploadResult?> upload(
    Uint8List encryptedBackup, {
    required String suggestedName,
  });

  /// Downloads the newest encrypted backup selected by the user.
  Future<PickedBackupFile?> downloadLatest();
}

/// Stable failure safe to show without leaking credentials or file contents.
class CloudBackupException implements Exception {
  const CloudBackupException(this.message);

  final String message;

  @override
  String toString() => message;
}
