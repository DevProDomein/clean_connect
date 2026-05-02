import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// CRM list: [Image.network] in a circle when [logoUrl] is set; [errorBuilder] → letter.
class RelationLogoAvatar extends StatelessWidget {
  const RelationLogoAvatar({
    super.key,
    required this.logoUrl,
    required this.fallbackLetter,
    this.accentColor,
    this.size = 50,
  });

  final String? logoUrl;
  final String fallbackLetter;
  final Color? accentColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ac = accentColor ?? Theme.of(context).colorScheme.primary;
    final url = logoUrl?.trim();
    if (url == null || url.isEmpty) {
      return _letterCircle(ac);
    }
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              color: ac.withValues(alpha: 0.08),
              alignment: Alignment.center,
              child: SizedBox(
                width: size * 0.35,
                height: size * 0.35,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: ac.withValues(alpha: 0.5),
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) => _letterCircle(ac),
        ),
      ),
    );
  }

  Widget _letterCircle(Color ac) {
    final t = fallbackLetter.trim();
    final L = t.isEmpty ? '?' : t.substring(0, 1).toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ac.withValues(alpha: 0.12),
      ),
      child: Text(
        L,
        style: GoogleFonts.lato(
          fontWeight: FontWeight.w900,
          fontSize: size * 0.36,
          color: ac,
        ),
      ),
    );
  }
}

/// Apple-style list avatar: [CachedNetworkImage] when [imageUrl] is valid, else letter.
class NetworkCircleAvatar extends StatelessWidget {
  const NetworkCircleAvatar({
    super.key,
    required this.imageUrl,
    required this.fallbackLetter,
    this.size = 50,
    this.accentColor,
  });

  final String? imageUrl;
  final String fallbackLetter;
  final double size;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final ac = accentColor ?? Theme.of(context).colorScheme.primary;
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) {
      return _letterCircle(ac);
    }
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: (context, u) => Container(
            color: ac.withValues(alpha: 0.08),
            alignment: Alignment.center,
            child: SizedBox(
              width: size * 0.35,
              height: size * 0.35,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: ac.withValues(alpha: 0.5),
              ),
            ),
          ),
          errorWidget: (context, u, e) => _letterCircle(ac),
        ),
      ),
    );
  }

  Widget _letterCircle(Color ac) {
    final t = fallbackLetter.trim();
    final L = t.isEmpty ? '?' : t.substring(0, 1).toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ac.withValues(alpha: 0.12),
      ),
      child: Text(
        L,
        style: GoogleFonts.lato(
          fontWeight: FontWeight.w900,
          fontSize: size * 0.36,
          color: ac,
        ),
      ),
    );
  }
}

/// Rounded rectangle image for project cards (pand / logo).
class NetworkRoundedImage extends StatelessWidget {
  const NetworkRoundedImage({
    super.key,
    required this.imageUrl,
    required this.fallbackLetter,
    this.width = 60,
    this.height = 60,
    this.borderRadius = 12,
    this.accentColor,
  });

  final String? imageUrl;
  final String fallbackLetter;
  final double width;
  final double height;
  final double borderRadius;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final ac = accentColor ?? const Color(0xFF2563EB);
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) {
      return _fallback(ac);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: width,
        height: height,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: (context, u) => Container(
            color: Colors.grey.shade100,
            alignment: Alignment.center,
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: ac.withValues(alpha: 0.5),
              ),
            ),
          ),
          errorWidget: (context, u, e) => _fallback(ac),
        ),
      ),
    );
  }

  Widget _fallback(Color ac) {
    final t = fallbackLetter.trim();
    final L = t.isEmpty ? '?' : t.substring(0, 1).toUpperCase();
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ac.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Text(
        L,
        style: GoogleFonts.lato(
          fontWeight: FontWeight.w900,
          fontSize: height * 0.32,
          color: ac,
        ),
      ),
    );
  }
}
