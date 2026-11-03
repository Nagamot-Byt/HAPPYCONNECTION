import 'package:flutter/material.dart';
import 'package:medlink_connect/features/ui/home_controller.dart';
import 'package:medlink_connect/features/ui/widgets/glass_container.dart';

class GuidancePanel extends StatelessWidget {
  final HomeController controller;

  const GuidancePanel({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    if (controller.guidanceTitle == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scheme = theme.colorScheme;
    final containerColor = controller.guidanceIsError
        ? scheme.errorContainer
        : scheme.primaryContainer;
    final iconColor =
        controller.guidanceIsError ? scheme.error : scheme.primary;

    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: GlassContainer(
        color: containerColor.withValues(alpha: isDark ? 0.45 : 0.65),
        borderColor: containerColor.withValues(alpha: isDark ? 0.6 : 0.8),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                controller.guidanceIsError
                    ? Icons.warning_amber_rounded
                    : Icons.tips_and_updates_outlined,
                color: iconColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.guidanceTitle!,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (controller.guidanceBullets.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      for (final bullet in controller.guidanceBullets)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6.0),
                          child: Text('• $bullet'),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
