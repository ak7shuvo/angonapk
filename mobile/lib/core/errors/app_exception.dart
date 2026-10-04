/// Typed application errors. Repositories translate transport failures into
/// these so UI code never deals with raw HTTP or socket exceptions.
sealed class AppException implements Exception {
  const AppException(this.message);

  /// Human-readable, safe to show to the user.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// No connectivity / server unreachable / timeout.
class NetworkException extends AppException {
  const NetworkException([
    super.message = 'Cannot reach ANGON. Check your connection.',
  ]);
}

/// 401 — missing or invalid credentials.
class UnauthorizedException extends AppException {
  const UnauthorizedException([super.message = 'Please sign in to continue.']);
}

/// 403 — authenticated but not allowed.
class ForbiddenException extends AppException {
  const ForbiddenException([
    super.message = 'You do not have permission to do that.',
  ]);
}

/// 404.
class NotFoundException extends AppException {
  const NotFoundException([super.message = 'We could not find that.']);
}

/// 422 / 400 — invalid input; [fieldErrors] maps field name to message.
class ValidationException extends AppException {
  const ValidationException(super.message, {this.fieldErrors = const {}});
  final Map<String, String> fieldErrors;
}

/// 5xx or unexpected response.
class ServerException extends AppException {
  const ServerException([
    super.message = 'Something went wrong on our side. Please try again.',
  ]);
}
