/// Stable failure categories that callers may expose without leaking secrets.
enum VaultUnlockFailureKind {
  /// The password-derived key could not authenticate the wrapped Vault key.
  invalidCredential,

  /// The DEK was recovered, but AES-GCM could not authenticate the payload.
  payloadAuthenticationFailed,

  /// The payload authenticated, but was not valid UTF-8 JSON object data.
  payloadJsonInvalid,

  /// The payload JSON decrypted, but its domain schema was incompatible.
  payloadSchemaIncompatible,

  /// Legacy aggregate retained for callers compiled against older revisions.
  corruptedPayload,

  /// The encrypted envelope could not be read or decoded.
  unreadableVault,

  /// A generic failure whose more specific cause is not known.
  unknown,
}

/// Raised when a vault cannot be authenticated or decrypted.
class VaultUnlockException implements Exception {
  const VaultUnlockException([
    this.message = 'Unable to unlock the vault.',
    this.kind = VaultUnlockFailureKind.unknown,
  ]);

  final String message;
  final VaultUnlockFailureKind kind;

  @override
  String toString() => 'VaultUnlockException: $message';
}
