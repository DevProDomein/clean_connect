import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class EnterprisePillBadge extends StatelessWidget {
  const EnterprisePillBadge({
    super.key,
    required this.text,
    this.backgroundColor,
    this.textColor,
    this.borderColor,
    this.textStyle,
    this.padding = const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
    this.radius = 24.0,
    this.centerText = true,
  });

  final String text;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? borderColor;
  final TextStyle? textStyle;

  /// MUST have explicit internal padding (client requirement).
  final EdgeInsets padding;

  /// MUST use BorderRadius.circular(24.0) (client requirement).
  final double radius;

  /// MUST center the text (client requirement).
  final bool centerText;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = backgroundColor ?? cs.onSurface.withValues(alpha: 0.08);
    final Color? autoFg = (textColor != null)
        ? textColor
        : (bg.a == 0.0
            ? null
            : (ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
                ? Colors.white
                : const Color(0xFF1C1C1E)));
    final fg = autoFg ?? cs.onSurface.withValues(alpha: 0.82);
    final border = borderColor ?? fg.withValues(alpha: 0.18);

    final baseStyle = (textStyle ?? DefaultTextStyle.of(context).style).copyWith(
      fontWeight: FontWeight.bold,
      letterSpacing: -0.2,
      fontSize: (textStyle?.fontSize ?? DefaultTextStyle.of(context).style.fontSize) ?? 12,
      color: (autoFg ?? textStyle?.color ?? DefaultTextStyle.of(context).style.color),
    );

    final child = Text(
      text,
      textAlign: centerText ? TextAlign.center : TextAlign.start,
      style: GoogleFonts.inter(textStyle: baseStyle).copyWith(color: fg),
    );

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border),
      ),
      child: centerText ? Center(child: child) : child,
    );
  }
}

