import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

/// Returns true when the signed-in user has [permission].
bool canAccess(BuildContext context, String permission) {
  try {
    return context.read<AuthProvider>().hasPermission(permission);
  } catch (_) {
    return false;
  }
}

/// True when the user may see purchase prices / purchase monetary data.
bool canViewPurchaseData(BuildContext context) {
  try {
    return context.read<AuthProvider>().canViewPurchaseData;
  } catch (_) {
    return false;
  }
}

/// Hides [child] when the user lacks [permission].
class PermissionGate extends StatelessWidget {
  const PermissionGate({
    super.key,
    required this.permission,
    required this.child,
    this.fallback = const SizedBox.shrink(),
  });

  final String permission;
  final Widget child;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final allowed = context.watch<AuthProvider>().hasPermission(permission);
    return allowed ? child : fallback;
  }
}

/// Hides purchase-price / cost UI when the user lacks purchases access.
class PurchaseDataGate extends StatelessWidget {
  const PurchaseDataGate({
    super.key,
    required this.child,
    this.fallback = const SizedBox.shrink(),
  });

  final Widget child;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final allowed = context.watch<AuthProvider>().canViewPurchaseData;
    return allowed ? child : fallback;
  }
}
