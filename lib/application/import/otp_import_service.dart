import 'dart:isolate';
import 'dart:typed_data';

import '../../domain/entities/account_draft.dart';
import '../../domain/import/google_authenticator_migration.dart';
import '../../domain/import/otp_import_candidate.dart';
import '../../domain/totp/otp_auth_uri_codec.dart';
import '../../platform/qr/qr_code_service.dart';

/// Safe, user-facing failure raised while turning external data into an account.
class OtpImportException implements Exception {
  const OtpImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Parsed QR input before the UI decides between single and batch confirmation.
sealed class OtpImportResult {
  const OtpImportResult();
}

/// One standard `otpauth://totp` account.
final class SingleOtpImportResult extends OtpImportResult {
  const SingleOtpImportResult(this.candidate);

  final OtpImportCandidate candidate;
}

/// One QR part from a Google Authenticator migration batch.
final class GoogleMigrationOtpImportResult extends OtpImportResult {
  const GoogleMigrationOtpImportResult(this.part);

  final GoogleMigrationPart part;
}

/// Converts image or QR text inputs into validated TOTP import candidates.
class OtpImportService {
  const OtpImportService({
    this.maxImageBytes = 20 * 1024 * 1024,
    this.maxImagePixels = 40 * 1000 * 1000,
  });

  final int maxImageBytes;
  final int maxImagePixels;

  /// Decodes one QR image outside the UI isolate and identifies its payload.
  Future<OtpImportResult> decodeImageBytes(
    Uint8List bytes, {
    OtpImportSource source = OtpImportSource.imageFile,
  }) async {
    if (bytes.isEmpty) {
      throw const OtpImportException('所选图片为空，无法识别二维码。');
    }
    if (bytes.length > maxImageBytes) {
      final limitMb = maxImageBytes ~/ (1024 * 1024);
      throw OtpImportException('图片超过 $limitMb MB 限制，请裁剪后重试。');
    }

    late final String payload;
    try {
      payload = await Isolate.run(
        () => QrCodeService().decodeImage(bytes, maxPixels: maxImagePixels),
      );
    } on FormatException {
      throw const OtpImportException('未识别到可用二维码。请确认图片清晰、完整，并只包含标准 TOTP 二维码。');
    } on Object {
      throw const OtpImportException('二维码图片解析失败，请更换图片后重试。');
    }

    return decodeQrText(payload, source: source);
  }

  /// Backward-compatible single-account API used by existing call sites/tests.
  Future<OtpImportCandidate> fromImageBytes(
    Uint8List bytes, {
    OtpImportSource source = OtpImportSource.imageFile,
  }) async {
    final result = await decodeImageBytes(bytes, source: source);
    if (result case SingleOtpImportResult(:final candidate)) return candidate;
    throw const OtpImportException(
      '该二维码是 Google Authenticator 批量迁移数据，请使用批量导入流程。',
    );
  }

  /// Identifies standard TOTP and Google Authenticator migration QR text.
  OtpImportResult decodeQrText(
    String payload, {
    required OtpImportSource source,
  }) {
    final trimmed = payload.trim();
    if (trimmed.toLowerCase().startsWith('otpauth-migration://')) {
      try {
        final part = GoogleAuthenticatorMigrationCodec().parse(trimmed);
        return GoogleMigrationOtpImportResult(part);
      } on FormatException {
        throw const OtpImportException(
          'Google Authenticator 迁移二维码无效、损坏或包含不受支持的数据。',
        );
      }
    }

    try {
      final config = OtpAuthUriCodec().parse(trimmed);
      return SingleOtpImportResult(
        OtpImportCandidate(
          draft: AccountDraft.fromConfig(config),
          source: source,
        ),
      );
    } on FormatException {
      final inputLabel = source == OtpImportSource.clipboardText
          ? '剪贴板内容'
          : '二维码';
      throw OtpImportException(
        '$inputLabel不是受支持的 TOTP 账号。当前支持标准 otpauth://totp 链接和 Google Authenticator 迁移二维码。',
      );
    }
  }

  /// Parses one standard TOTP QR text without retaining its raw URI.
  OtpImportCandidate fromQrText(
    String payload, {
    required OtpImportSource source,
  }) {
    final result = decodeQrText(payload, source: source);
    if (result case SingleOtpImportResult(:final candidate)) return candidate;
    throw const OtpImportException(
      '该二维码是 Google Authenticator 批量迁移数据，请使用批量导入流程。',
    );
  }
}
