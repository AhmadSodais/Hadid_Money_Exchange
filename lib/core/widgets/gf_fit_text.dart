import 'package:flutter/material.dart';

/// Text that shrinks to fit its max width instead of truncating with ellipsis.
///
/// Use for titles, nav labels, and KPI headings where readability matters more
/// than a hard ellipsis. Long free-form strings (descriptions, table notes)
/// should keep [TextOverflow.ellipsis].
class GfFitText extends StatelessWidget {
  const GfFitText(
    this.data, {
    super.key,
    this.style,
    this.maxLines = 1,
    this.textAlign,
    this.textDirection,
  });

  final String data;
  final TextStyle? style;
  final int maxLines;
  final TextAlign? textAlign;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    final alignment = switch (textAlign) {
      TextAlign.center => Alignment.center,
      TextAlign.left || TextAlign.start => Alignment.centerLeft,
      TextAlign.right || TextAlign.end => Alignment.centerRight,
      _ => AlignmentDirectional.centerStart,
    };

    // Multi-line: wrap normally; still allow scale-down of the whole block.
    if (maxLines > 1) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: Text(
          data,
          style: style,
          maxLines: maxLines,
          textAlign: textAlign,
          textDirection: textDirection,
          softWrap: true,
        ),
      );
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignment,
      child: Text(
        data,
        style: style,
        maxLines: 1,
        softWrap: false,
        textAlign: textAlign,
        textDirection: textDirection,
      ),
    );
  }
}
