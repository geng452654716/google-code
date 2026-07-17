import 'dart:typed_data';

import '../../domain/entities/account.dart';
import '../../domain/totp/otp_auth_uri_codec.dart';
import '../../platform/qr/qr_code_service.dart';

/// Ephemeral credentials generated only after a successful reauthentication.
class AccountShareMaterial {
  const AccountShareMaterial({
    required this.secret,
    required this.otpAuthUri,
    required this.qrPng,
  });

  final String secret;
  final String otpAuthUri;
  final Uint8List qrPng;
}

/// Builds standards-compatible single-account sharing material in memory.
class AccountShareService {
  AccountShareService({OtpAuthUriCodec? uriCodec, QrCodeService? qrCodeService})
    : _uriCodec = uriCodec ?? OtpAuthUriCodec(),
      _qrCodeService = qrCodeService ?? QrCodeService();

  final OtpAuthUriCodec _uriCodec;
  final QrCodeService _qrCodeService;

  /// Generates Secret, URI and QR PNG without persisting or logging them.
  AccountShareMaterial create(Account account) {
    final uri = _uriCodec.encode(account.toTotpConfig());
    return AccountShareMaterial(
      secret: account.secret,
      otpAuthUri: uri,
      qrPng: _qrCodeService.encodePng(uri),
    );
  }
}
