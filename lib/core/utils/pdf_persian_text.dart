import 'package:bidi/bidi.dart' as bidi;

/// Persian / Arabic helpers for `package:pdf` text rendering.
///
/// `package:pdf` maps glyphs by Unicode codepoint and does not run OpenType
/// GSUB. Modern UI fonts (Vazirmatn, YekanBakh) often lack Arabic
/// *Presentation Forms*, so letters disconnect or stack. The fix is:
/// 1. Convert logical RTL text to visual order with contextual forms via [bidi]
/// 2. Embed a font that includes Presentation Forms (Noto Naskh Arabic)
/// 3. Draw the result as LTR so the engine does not reshape twice
abstract final class PdfPersianText {
  static final RegExp _rtlScriptRe = RegExp(
    r'[\u0590-\u05FF\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF'
    r'\uFB50-\uFDFF\uFE70-\uFEFF]',
  );

  static bool containsRtl(String text) => _rtlScriptRe.hasMatch(text);

  /// Normalize common Persian codepoints before shaping.
  static String normalize(String input) {
    if (input.isEmpty) return input;
    return input
        // Arabic Yeh / Kaf → Persian Yeh / Keheh
        .replaceAll('\u064A', '\u06CC')
        .replaceAll('\u0643', '\u06A9')
        // Prefer ZWNJ over ZWJ for Persian word boundaries
        .replaceAll('\u200D', '\u200C');
  }

  /// Returns text ready for PDF drawing (visual order + joined forms).
  ///
  /// Latin / digit-only strings are returned unchanged.
  static String shape(String input) {
    final text = normalize(input);
    if (text.isEmpty || !containsRtl(text)) return text;
    try {
      final visual = String.fromCharCodes(bidi.logicalToVisual(text));
      // ZWNJ/LRM/etc. can paint as a visible “dot/circle” over letters in PDF.
      return visual.replaceAll(
        RegExp(r'[\u200B-\u200F\u202A-\u202E\u2060\uFEFF]'),
        '',
      );
    } catch (_) {
      return text;
    }
  }
}