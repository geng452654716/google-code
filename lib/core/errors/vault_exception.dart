/// Stable failure categories that callers may expose without leaking secrets.
enum VaultUnlockFailureKind {
  /// The password-derived key could not authenticate the wrapped Vault key.
  invalidCredential,

  /// The Vault key was accepted, but the encrypted payload was invalid.
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
