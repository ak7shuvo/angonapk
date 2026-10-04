/// Client-side checks mirroring the API rules, for fast feedback only.
/// The server remains authoritative.
abstract final class Validators {
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _username = RegExp(r'^[a-zA-Z0-9_]{3,30}$');

  static String? email(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'Enter your email';
    if (!_email.hasMatch(value)) return 'Enter a valid email address';
    return null;
  }

  static String? username(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'Choose a username';
    if (!_username.hasMatch(value)) {
      return '3–30 characters: letters, numbers, underscores';
    }
    return null;
  }

  static String? newPassword(String? v) {
    final value = v ?? '';
    if (value.isEmpty) return 'Choose a password';
    if (value.length < 8) return 'Use at least 8 characters';
    if (value.length > 128) return 'Use at most 128 characters';
    return null;
  }

  static String? required(String? v, String message) =>
      (v == null || v.trim().isEmpty) ? message : null;
}
