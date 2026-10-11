import '../errors/app_failure.dart';

/// Functional result wrapper for use cases and repositories.
sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is FailureResult<T>;

  T? get valueOrNull => switch (this) {
        Success(:final value) => value,
        FailureResult() => null,
      };

  AppFailure? get failureOrNull => switch (this) {
        Success() => null,
        FailureResult(:final failure) => failure,
      };

  /// Convenience accessor — only valid on [FailureResult]. Prefer [failureOrNull].
  AppFailure get failure =>
      failureOrNull ?? (throw StateError('Result is not a failure'));

  R when<R>({
    required R Function(T value) success,
    required R Function(AppFailure error) failure,
  }) {
    final self = this;
    if (self is Success<T>) return success(self.value);
    if (self is FailureResult<T>) return failure(self.failure);
    throw StateError('Unknown Result subtype');
  }

  Result<R> map<R>(R Function(T value) transform) {
    final self = this;
    if (self is Success<T>) return Success(transform(self.value));
    if (self is FailureResult<T>) return FailureResult(self.failure);
    throw StateError('Unknown Result subtype');
  }
}

final class Success<T> extends Result<T> {
  const Success(this.value);
  final T value;
}

final class FailureResult<T> extends Result<T> {
  const FailureResult(this._failure);
  final AppFailure _failure;

  @override
  AppFailure get failure => _failure;
}
