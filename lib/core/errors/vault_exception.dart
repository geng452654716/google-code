/// Raised when a vault cannot be authenticated or decrypted.
class VaultUnlockException implements Exception {
  const VaultUnlockException([this.message = 'Unable to unlock the vault.']);

  final String message;

  @override
  String toString() => 'VaultUnlockException: $message';
}
