/// Domain / data layer failures.
sealed class AppFailure implements Exception {
  const AppFailure(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

final class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message, {super.cause, this.fieldErrors = const {}});

  final Map<String, String> fieldErrors;
}

final class DatabaseFailure extends AppFailure {
  const DatabaseFailure(super.message, {super.cause});
}

final class NotFoundFailure extends AppFailure {
  const NotFoundFailure(super.message, {super.cause});
}

final class ConflictFailure extends AppFailure {
  const ConflictFailure(super.message, {super.cause});
}

final class PermissionFailure extends AppFailure {
  const PermissionFailure(super.message, {super.cause});
}

final class FileFailure extends AppFailure {
  const FileFailure(super.message, {super.cause});
}

final class UnknownFailure extends AppFailure {
  const UnknownFailure(super.message, {super.cause});
}
