/// Validation rules for the local master password.
class PasswordPolicy {
  const PasswordPolicy({this.minimumLength = 8});

  final int minimumLength;

  /// Returns a user-facing validation message, or `null` when valid.
  ///
  /// [label] lets other local secrets reuse the same minimum-length rule.
  String? validate(String password, {String label = '主密码'}) {
    if (password.isEmpty) return '请输入$label';
    if (password.length < minimumLength) {
      return '$label至少需要 $minimumLength 个字符';
    }
    return null;
  }
}
