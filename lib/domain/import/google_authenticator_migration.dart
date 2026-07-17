import 'dart:convert';
import 'dart:typed_data';

import '../../core/encoding/base32_codec.dart';
import '../entities/account_draft.dart';
import '../totp/totp_algorithm.dart';
import 'otp_import_candidate.dart';

/// One decoded Google Authenticator migration entry.
///
/// Invalid or unsupported entries retain only safe display metadata and a
/// user-facing issue. Raw protobuf bytes and secrets are not kept for them.
class GoogleMigrationEntry {
  const GoogleMigrationEntry._({
    required this.issuer,
    required this.accountName,
    this.candidate,
    this.issue,
  });

  factory GoogleMigrationEntry.valid({
    required String issuer,
    required String accountName,
    required AccountDraft draft,
  }) => GoogleMigrationEntry._(
    issuer: issuer,
    accountName: accountName,
    candidate: OtpImportCandidate(
      draft: draft,
      source: OtpImportSource.googleMigration,
    ),
  );

  factory GoogleMigrationEntry.invalid({
    required String issuer,
    required String accountName,
    required String issue,
  }) => GoogleMigrationEntry._(
    issuer: issuer,
    accountName: accountName,
    issue: issue,
  );

  final String issuer;
  final String accountName;
  final OtpImportCandidate? candidate;
  final String? issue;

  bool get isValid => candidate != null;
}

/// One QR code from a potentially multi-code Google migration batch.
class GoogleMigrationPart {
  const GoogleMigrationPart({
    required this.version,
    required this.batchSize,
    required this.batchIndex,
    required this.batchId,
    required this.entries,
  });

  final int version;
  final int batchSize;
  final int batchIndex;
  final int batchId;
  final List<GoogleMigrationEntry> entries;
}

/// Result of adding a migration QR to an in-memory batch collector.
enum GoogleMigrationPartAddResult { added, duplicate }

/// Collects migration QR parts without persisting an incomplete batch.
class GoogleMigrationBatchAccumulator {
  GoogleMigrationBatchAccumulator._({
    required this.batchId,
    required this.batchSize,
  });

  factory GoogleMigrationBatchAccumulator.fromPart(GoogleMigrationPart part) {
    final accumulator = GoogleMigrationBatchAccumulator._(
      batchId: part.batchId,
      batchSize: part.batchSize,
    );
    accumulator._parts[part.batchIndex] = part;
    return accumulator;
  }

  final int batchId;
  final int batchSize;
  final Map<int, GoogleMigrationPart> _parts = {};

  int get receivedPartCount => _parts.length;
  bool get isComplete => receivedPartCount == batchSize;

  /// Returns entries in QR index order after the whole batch is available.
  List<GoogleMigrationEntry> get entries {
    final indexes = _parts.keys.toList()..sort();
    return List.unmodifiable(indexes.expand((index) => _parts[index]!.entries));
  }

  /// Adds a part from the same batch and never replaces an already-seen index.
  GoogleMigrationPartAddResult add(GoogleMigrationPart part) {
    if (part.batchId != batchId || part.batchSize != batchSize) {
      throw const FormatException('Migration QR belongs to another batch.');
    }
    if (_parts.containsKey(part.batchIndex)) {
      return GoogleMigrationPartAddResult.duplicate;
    }
    _parts[part.batchIndex] = part;
    return GoogleMigrationPartAddResult.added;
  }
}

/// Decodes Google Authenticator `otpauth-migration://` protobuf payloads.
///
/// A small bounded wire reader is used instead of retaining generated protobuf
/// objects, keeping the offline import surface narrow and auditable.
class GoogleAuthenticatorMigrationCodec {
  GoogleAuthenticatorMigrationCodec({Base32Codec? base32Codec})
    : _base32Codec = base32Codec ?? Base32Codec();

  static const _maxEncodedDataChars = 128 * 1024;
  static const _maxPayloadBytes = 96 * 1024;
  static const _maxEntriesPerPart = 100;
  static const _maxSecretBytes = 1024;
  static const _maxTextBytes = 4096;
  static const _maxBatchSize = 100;

  final Base32Codec _base32Codec;

  GoogleMigrationPart parse(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'otpauth-migration') {
      throw const FormatException('Expected an otpauth-migration URI.');
    }
    if (uri.host.toLowerCase() != 'offline') {
      throw const FormatException('Unsupported migration URI host.');
    }

    final encoded = uri.queryParameters['data'];
    if (encoded == null || encoded.isEmpty) {
      throw const FormatException('Migration payload is missing.');
    }
    if (encoded.length > _maxEncodedDataChars) {
      throw const FormatException('Migration payload is too large.');
    }

    late final Uint8List payloadBytes;
    try {
      final normalized = encoded.replaceAll(' ', '+');
      final padding = '=' * ((4 - normalized.length % 4) % 4);
      payloadBytes = Uint8List.fromList(
        base64Url.decode('$normalized$padding'),
      );
    } on FormatException {
      throw const FormatException('Migration payload is not valid Base64.');
    }
    if (payloadBytes.isEmpty || payloadBytes.length > _maxPayloadBytes) {
      throw const FormatException('Migration payload size is invalid.');
    }

    final reader = _ProtoReader(payloadBytes);
    final entries = <GoogleMigrationEntry>[];
    var version = 0;
    var batchSize = 0;
    var batchIndex = 0;
    var batchId = 0;

    while (!reader.isAtEnd) {
      final tag = reader.readVarint();
      final field = tag >> 3;
      final wireType = tag & 0x07;
      if (field == 0) throw const FormatException('Invalid protobuf field.');
      switch (field) {
        case 1:
          if (wireType != 2) {
            throw const FormatException('Invalid account field encoding.');
          }
          if (entries.length >= _maxEntriesPerPart) {
            throw const FormatException(
              'Migration QR contains too many accounts.',
            );
          }
          entries.add(_parseEntry(reader.readBytes(_maxPayloadBytes)));
        case 2:
          version = _readInt32(reader, wireType);
        case 3:
          batchSize = _readInt32(reader, wireType);
        case 4:
          batchIndex = _readInt32(reader, wireType);
        case 5:
          batchId = _readInt32(reader, wireType);
        default:
          reader.skipField(wireType);
      }
    }

    if (version != 1) {
      throw const FormatException('Unsupported migration payload version.');
    }
    final normalizedBatchSize = batchSize == 0 ? 1 : batchSize;
    if (normalizedBatchSize < 1 || normalizedBatchSize > _maxBatchSize) {
      throw const FormatException('Migration batch size is invalid.');
    }
    if (batchIndex < 0 || batchIndex >= normalizedBatchSize) {
      throw const FormatException('Migration batch index is invalid.');
    }
    if (entries.isEmpty) {
      throw const FormatException('Migration QR contains no accounts.');
    }

    return GoogleMigrationPart(
      version: version,
      batchSize: normalizedBatchSize,
      batchIndex: batchIndex,
      batchId: batchId,
      entries: List.unmodifiable(entries),
    );
  }

  GoogleMigrationEntry _parseEntry(Uint8List bytes) {
    final reader = _ProtoReader(bytes);
    Uint8List? secret;
    var name = '';
    var issuer = '';
    var algorithm = 0;
    var digits = 0;
    var type = 0;

    while (!reader.isAtEnd) {
      final tag = reader.readVarint();
      final field = tag >> 3;
      final wireType = tag & 0x07;
      if (field == 0) throw const FormatException('Invalid account field.');
      switch (field) {
        case 1:
          if (wireType != 2) {
            throw const FormatException('Invalid secret field encoding.');
          }
          secret = reader.readBytes(_maxSecretBytes);
        case 2:
          name = _readString(reader, wireType);
        case 3:
          issuer = _readString(reader, wireType);
        case 4:
          algorithm = _readInt32(reader, wireType);
        case 5:
          digits = _readInt32(reader, wireType);
        case 6:
          type = _readInt32(reader, wireType);
        default:
          reader.skipField(wireType);
      }
    }

    final normalized = _normalizeLabel(issuer, name);
    GoogleMigrationEntry invalid(String issue) => GoogleMigrationEntry.invalid(
      issuer: normalized.$1,
      accountName: normalized.$2,
      issue: issue,
    );

    if (secret == null || secret.isEmpty) return invalid('Secret 为空');
    if (normalized.$2.isEmpty) return invalid('账号名称为空');
    if (type != 2) {
      return invalid(type == 1 ? 'HOTP 暂不支持' : '验证码类型不受支持');
    }

    final parsedAlgorithm = switch (algorithm) {
      0 || 1 => TotpAlgorithm.sha1,
      2 => TotpAlgorithm.sha256,
      3 => TotpAlgorithm.sha512,
      _ => null,
    };
    if (parsedAlgorithm == null) return invalid('验证码算法不受支持');

    final parsedDigits = switch (digits) {
      0 || 1 => 6,
      2 => 8,
      _ => null,
    };
    if (parsedDigits == null) return invalid('验证码位数不受支持');

    final draft = AccountDraft(
      issuer: normalized.$1,
      accountName: normalized.$2,
      secret: _base32Codec.encode(secret),
      algorithm: parsedAlgorithm,
      digits: parsedDigits,
      periodSeconds: 30,
    );
    return GoogleMigrationEntry.valid(
      issuer: draft.issuer,
      accountName: draft.accountName,
      draft: draft,
    );
  }

  (String, String) _normalizeLabel(String issuer, String name) {
    var normalizedIssuer = issuer.trim();
    var accountName = name.trim();
    final separator = accountName.indexOf(':');
    if (normalizedIssuer.isEmpty && separator > 0) {
      normalizedIssuer = accountName.substring(0, separator).trim();
      accountName = accountName.substring(separator + 1).trim();
    } else if (normalizedIssuer.isNotEmpty && separator > 0) {
      final nameIssuer = accountName.substring(0, separator).trim();
      if (nameIssuer.toLowerCase() == normalizedIssuer.toLowerCase()) {
        accountName = accountName.substring(separator + 1).trim();
      }
    }
    return (normalizedIssuer, accountName);
  }

  int _readInt32(_ProtoReader reader, int wireType) {
    if (wireType != 0) throw const FormatException('Expected varint field.');
    final value = reader.readVarint();
    if (value > 0x7fffffff) {
      throw const FormatException('Integer field is out of range.');
    }
    return value;
  }

  String _readString(_ProtoReader reader, int wireType) {
    if (wireType != 2) {
      throw const FormatException('Expected length-delimited string.');
    }
    try {
      return utf8.decode(
        reader.readBytes(_maxTextBytes),
        allowMalformed: false,
      );
    } on FormatException {
      throw const FormatException('Migration text is not valid UTF-8.');
    }
  }
}

class _ProtoReader {
  _ProtoReader(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  bool get isAtEnd => _offset == _bytes.length;

  int readVarint() {
    var result = 0;
    for (var shift = 0; shift < 64; shift += 7) {
      if (_offset >= _bytes.length) {
        throw const FormatException('Truncated protobuf varint.');
      }
      final byte = _bytes[_offset++];
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) return result;
    }
    throw const FormatException('Protobuf varint is too long.');
  }

  Uint8List readBytes(int maxLength) {
    final length = readVarint();
    if (length < 0 || length > maxLength || length > _bytes.length - _offset) {
      throw const FormatException('Invalid protobuf field length.');
    }
    final result = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    return result;
  }

  void skipField(int wireType) {
    switch (wireType) {
      case 0:
        readVarint();
      case 1:
        _skip(8);
      case 2:
        final length = readVarint();
        _skip(length);
      case 5:
        _skip(4);
      default:
        throw const FormatException('Unsupported protobuf wire type.');
    }
  }

  void _skip(int length) {
    if (length < 0 || length > _bytes.length - _offset) {
      throw const FormatException('Truncated protobuf field.');
    }
    _offset += length;
  }
}
