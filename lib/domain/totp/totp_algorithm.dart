/// Hash algorithms supported by TOTP according to RFC 6238.
enum TotpAlgorithm {
  sha1('SHA1'),
  sha256('SHA256'),
  sha512('SHA512');

  const TotpAlgorithm(this.otpAuthName);

  /// Algorithm name used by `otpauth://` URIs.
  final String otpAuthName;

  /// Parses an `otpauth://` algorithm value.
  static TotpAlgorithm parse(String? value) {
    final normalized = (value ?? 'SHA1').toUpperCase().replaceAll('-', '');
    return TotpAlgorithm.values.firstWhere(
      (algorithm) => algorithm.otpAuthName == normalized,
      orElse: () => throw FormatException('Unsupported TOTP algorithm: $value'),
    );
  }
}
