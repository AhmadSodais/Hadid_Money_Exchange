/// Typed financial domain errors.
///
/// Every error carries a stable [code] (for tests and logs) and a Persian
/// [message] that the presentation layer can show as-is.
sealed class DomainError implements Exception {
  const DomainError(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

/// Input failed validation (amount, rate, date, missing field, precision).
final class ValidationError extends DomainError {
  const ValidationError(super.code, super.message, {this.field});

  final String? field;
}

/// A business rule forbids the operation (closed day, inactive customer,
/// repeated reversal, duplicate opening balance, ...).
final class BusinessRuleError extends DomainError {
  const BusinessRuleError(super.code, super.message);
}

/// The actor lacks the permission required for the operation.
final class AuthorizationError extends DomainError {
  const AuthorizationError(super.code, super.message);
}

/// A referenced record does not exist.
final class NotFoundError extends DomainError {
  const NotFoundError(super.code, super.message);
}

/// An accounting invariant was violated. This indicates a programming error
/// and must never be swallowed.
final class InvariantViolation extends DomainError {
  const InvariantViolation(super.code, super.message);
}

/// Persistence failed; the surrounding database transaction was rolled back.
final class PersistenceError extends DomainError {
  const PersistenceError(super.code, super.message, {this.cause});

  final Object? cause;
}
