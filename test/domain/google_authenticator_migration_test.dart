import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/application/import/otp_import_service.dart';
import 'package:google_code/core/encoding/base32_codec.dart';
import 'package:google_code/domain/import/google_authenticator_migration.dart';
import 'package:google_code/domain/import/otp_import_candidate.dart';
import 'package:google_code/domain/totp/totp.dart';
import 'package:google_code/platform/qr/qr_code_service.dart';

void main() {
  group('GoogleAuthenticatorMigrationCodec', () {
    test(
      'parses valid TOTP entries and retains unsupported entries as issues',
      () {
        final uri = _migrationUri(
          entries: [
            _otpEntry(
              secret: [1, 2, 3, 4, 5, 6, 7, 8],
              name: 'Example:alice@example.com',
              issuer: 'Example',
              algorithm: 2,
              digits: 2,
              type: 2,
            ),
            _otpEntry(
              secret: [9, 8, 7, 6],
              name: 'counter-account',
              issuer: 'Legacy',
              type: 1,
            ),
          ],
          batchSize: 2,
          batchIndex: 1,
          batchId: 42,
        );

        final part = GoogleAuthenticatorMigrationCodec().parse(uri);

        expect(part.version, 1);
        expect(part.batchSize, 2);
        expect(part.batchIndex, 1);
        expect(part.batchId, 42);
        expect(part.entries, hasLength(2));
        final valid = part.entries.first.candidate!;
        expect(valid.source, OtpImportSource.googleMigration);
        expect(valid.draft.issuer, 'Example');
        expect(valid.draft.accountName, 'alice@example.com');
        expect(
          valid.draft.secret,
          Base32Codec().encode([1, 2, 3, 4, 5, 6, 7, 8]),
        );
        expect(valid.draft.algorithm, TotpAlgorithm.sha256);
        expect(valid.draft.digits, 8);
        expect(valid.draft.periodSeconds, 30);
        expect(part.entries.last.isValid, isFalse);
        expect(part.entries.last.issue, 'HOTP 暂不支持');
      },
    );

    test('rejects unsupported payload versions without leaking raw data', () {
      final uri = _migrationUri(
        entries: [
          _otpEntry(
            secret: [1, 2, 3, 4],
            name: 'alice@example.com',
            issuer: 'Example',
            type: 2,
          ),
        ],
        version: 9,
      );

      expect(
        () => GoogleAuthenticatorMigrationCodec().parse(uri),
        throwsFormatException,
      );
    });
  });

  test('accumulates out-of-order QR parts and ignores duplicate scans', () {
    final first = GoogleAuthenticatorMigrationCodec().parse(
      _migrationUri(
        entries: [
          _otpEntry(
            secret: [1, 1, 1, 1],
            name: 'first@example.com',
            issuer: 'Example',
            type: 2,
          ),
        ],
        batchSize: 2,
        batchIndex: 0,
        batchId: 77,
      ),
    );
    final second = GoogleAuthenticatorMigrationCodec().parse(
      _migrationUri(
        entries: [
          _otpEntry(
            secret: [2, 2, 2, 2],
            name: 'second@example.com',
            issuer: 'Example',
            type: 2,
          ),
        ],
        batchSize: 2,
        batchIndex: 1,
        batchId: 77,
      ),
    );

    final accumulator = GoogleMigrationBatchAccumulator.fromPart(second);
    expect(accumulator.isComplete, isFalse);
    expect(accumulator.add(second), GoogleMigrationPartAddResult.duplicate);
    expect(accumulator.add(first), GoogleMigrationPartAddResult.added);
    expect(accumulator.isComplete, isTrue);
    expect(accumulator.entries.map((entry) => entry.accountName), [
      'first@example.com',
      'second@example.com',
    ]);
  });

  test('image import service identifies a migration QR payload', () async {
    final uri = _migrationUri(
      entries: [
        _otpEntry(
          secret: [1, 2, 3, 4, 5],
          name: 'alice@example.com',
          issuer: 'Example',
          type: 2,
        ),
      ],
    );
    final png = QrCodeService().encodePng(uri);

    final result = await const OtpImportService().decodeImageBytes(png);

    expect(result, isA<GoogleMigrationOtpImportResult>());
    final part = (result as GoogleMigrationOtpImportResult).part;
    expect(part.entries.single.accountName, 'alice@example.com');
  });
}

String _migrationUri({
  required List<Uint8List> entries,
  int version = 1,
  int batchSize = 1,
  int batchIndex = 0,
  int batchId = 1,
}) {
  final payload = BytesBuilder(copy: false);
  for (final entry in entries) {
    payload.add(_bytesField(1, entry));
  }
  payload
    ..add(_varintField(2, version))
    ..add(_varintField(3, batchSize))
    ..add(_varintField(4, batchIndex))
    ..add(_varintField(5, batchId));
  return 'otpauth-migration://offline?data='
      '${base64Url.encode(payload.toBytes()).replaceAll('=', '')}';
}

Uint8List _otpEntry({
  required List<int> secret,
  required String name,
  required String issuer,
  int algorithm = 1,
  int digits = 1,
  required int type,
}) {
  final entry = BytesBuilder(copy: false)
    ..add(_bytesField(1, Uint8List.fromList(secret)))
    ..add(_bytesField(2, Uint8List.fromList(utf8.encode(name))))
    ..add(_bytesField(3, Uint8List.fromList(utf8.encode(issuer))))
    ..add(_varintField(4, algorithm))
    ..add(_varintField(5, digits))
    ..add(_varintField(6, type));
  return entry.toBytes();
}

Uint8List _bytesField(int field, Uint8List value) => Uint8List.fromList([
  ..._varint((field << 3) | 2),
  ..._varint(value.length),
  ...value,
]);

Uint8List _varintField(int field, int value) =>
    Uint8List.fromList([..._varint(field << 3), ..._varint(value)]);

List<int> _varint(int value) {
  final bytes = <int>[];
  var remaining = value;
  do {
    var byte = remaining & 0x7f;
    remaining >>= 7;
    if (remaining != 0) byte |= 0x80;
    bytes.add(byte);
  } while (remaining != 0);
  return bytes;
}
