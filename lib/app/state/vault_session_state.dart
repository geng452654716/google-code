import '../../domain/entities/entities.dart';

/// High-level Vault screen shown by the application root.
enum VaultSessionPhase { loading, needsSetup, locked, unlocked, error }

/// Immutable application state that never retains the master password.
class VaultSessionState {
  const VaultSessionState({
    required this.phase,
    this.payload,
    this.searchQuery = '',
    this.isProcessing = false,
    this.message,
  });

  const VaultSessionState.loading()
    : phase = VaultSessionPhase.loading,
      payload = null,
      searchQuery = '',
      isProcessing = false,
      message = null;

  final VaultSessionPhase phase;
  final VaultPayload? payload;
  final String searchQuery;
  final bool isProcessing;
  final String? message;

  bool get isUnlocked => phase == VaultSessionPhase.unlocked && payload != null;

  /// Accounts filtered and ordered entirely in unlocked memory.
  List<Account> get visibleAccounts {
    final normalizedQuery = searchQuery.trim().toLowerCase();
    final source = payload?.accounts ?? const <Account>[];
    final filtered = normalizedQuery.isEmpty
        ? source.toList()
        : source.where((account) {
            final haystack = '${account.issuer} ${account.accountName}'
                .toLowerCase();
            return haystack.contains(normalizedQuery);
          }).toList();
    filtered.sort((left, right) {
      if (left.isPinned != right.isPinned) return left.isPinned ? -1 : 1;
      final sortOrder = left.sortOrder.compareTo(right.sortOrder);
      if (sortOrder != 0) return sortOrder;
      return '${left.issuer}\u0000${left.accountName}'.toLowerCase().compareTo(
        '${right.issuer}\u0000${right.accountName}'.toLowerCase(),
      );
    });
    return filtered;
  }

  VaultSessionState copyWith({
    VaultSessionPhase? phase,
    VaultPayload? payload,
    bool clearPayload = false,
    String? searchQuery,
    bool? isProcessing,
    String? message,
    bool clearMessage = false,
  }) => VaultSessionState(
    phase: phase ?? this.phase,
    payload: clearPayload ? null : payload ?? this.payload,
    searchQuery: searchQuery ?? this.searchQuery,
    isProcessing: isProcessing ?? this.isProcessing,
    message: clearMessage ? null : message ?? this.message,
  );
}
