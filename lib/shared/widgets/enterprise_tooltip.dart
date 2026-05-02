import 'package:flutter/material.dart';

/// Enterprise UX pattern: small "(i)" hint for complex terms.
///
/// Uses Flutter's built-in [Tooltip] (hover on desktop, long-press/tap on mobile).
class EnterpriseTooltip extends StatelessWidget {
  const EnterpriseTooltip({
    super.key,
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return const SizedBox.shrink();

    return Tooltip(
      message: trimmed,
      triggerMode: TooltipTriggerMode.longPress,
      child: const Icon(
        Icons.info_outline,
        size: 18,
        color: Colors.grey,
      ),
    );
  }
}

