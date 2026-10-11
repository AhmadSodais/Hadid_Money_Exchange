import 'package:flutter/material.dart';

/// GlassFlow corner radius tokens — unified at 8 across the app.
abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 8;
  static const double lg = 8;
  static const double xl = 8;

  static const BorderRadius card = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius modal = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius input = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius button = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
  static const BorderRadius navItem = BorderRadius.all(Radius.circular(sm));
}
