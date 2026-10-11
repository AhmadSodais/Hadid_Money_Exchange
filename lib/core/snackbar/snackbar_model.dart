import 'package:flutter/foundation.dart';

enum SnackbarType {
  success,
  error,
  warning,
  info,
  loading,
  action,
}

@immutable
class SnackbarModel {
  const SnackbarModel({
    required this.id,
    required this.title,
    required this.type,
    this.message,
    this.duration = const Duration(seconds: 4),
    this.actionLabel,
    this.onAction,
    this.progress,
    this.createdAt,
  });

  final String id;
  final String title;
  final String? message;
  final SnackbarType type;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// 0.0 – 1.0 for [SnackbarType.loading]; null hides the percentage label.
  final double? progress;
  final DateTime? createdAt;

  bool get isLoading => type == SnackbarType.loading;
  bool get hasAction =>
      type == SnackbarType.action &&
      actionLabel != null &&
      actionLabel!.trim().isNotEmpty &&
      onAction != null;

  SnackbarModel copyWith({
    String? title,
    String? message,
    SnackbarType? type,
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
    double? progress,
    bool clearProgress = false,
  }) {
    return SnackbarModel(
      id: id,
      title: title ?? this.title,
      message: message ?? this.message,
      type: type ?? this.type,
      duration: duration ?? this.duration,
      actionLabel: actionLabel ?? this.actionLabel,
      onAction: onAction ?? this.onAction,
      progress: clearProgress ? null : (progress ?? this.progress),
      createdAt: createdAt,
    );
  }
}
