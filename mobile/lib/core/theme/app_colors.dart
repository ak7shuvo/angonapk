import 'package:flutter/material.dart';

/// ANGON colour tokens: warm paper, deep ink, terracotta and delta-green.
/// Calm, editorial and photography-friendly. Avoid adding gradients.
abstract final class AppColors {
  // Surfaces
  static const paper = Color(0xFFFAF6EF);
  static const paperDeep = Color(0xFFF1EADD);
  static const card = Color(0xFFFFFFFF);

  // Ink
  static const ink = Color(0xFF1F1B16);
  static const inkSoft = Color(0xFF5E564B);
  static const inkFaint = Color(0xFF9A9183);
  static const line = Color(0xFFE4DCCB);

  // Brand
  static const terracotta = Color(0xFFB4532A);
  static const terracottaDeep = Color(0xFF8C3E1D);
  static const delta = Color(0xFF2F5D50);
  static const saffron = Color(0xFFD9A441);

  // Feedback
  static const error = Color(0xFFB3261E);
  static const success = Color(0xFF2E7D5B);

  // Dark mode
  static const nightPaper = Color(0xFF16130F);
  static const nightCard = Color(0xFF211D17);
  static const nightInk = Color(0xFFF3EDE2);
  static const nightInkSoft = Color(0xFFB8AF9F);
  static const nightLine = Color(0xFF3A342B);
}
