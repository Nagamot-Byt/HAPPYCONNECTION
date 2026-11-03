import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:medlink_connect/core/app_theme.dart';
import 'package:medlink_connect/features/ui/home_controller.dart';

class ConnectionStepIndicator extends StatelessWidget {
  final HomeController controller;

  const ConnectionStepIndicator({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    const steps = [
      ConnectionStep.diagnostics,
      ConnectionStep.splitTunnel,
      ConnectionStep.preLaunch,
      ConnectionStep.launchRdp,
    ];
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final successColor = AppTheme.successColor(theme.brightness);
    final labels = [
      l10n.stepPrepare,
      l10n.stepTunnel,
      l10n.stepVerify,
      l10n.stepOpenRdp,
    ];

    final currentIdx = steps.indexOf(controller.step);
    return Row(
      children: List.generate(steps.length, (i) {
        final s = steps[i];
        final active = controller.step == s;
        final done = controller.step == ConnectionStep.done ||
            (currentIdx != -1 && i < currentIdx);
        return Expanded(
          child: Semantics(
            label: labels[i],
            selected: active,
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Column(
                  children: [
                    Container(
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: done
                            ? successColor
                            : active
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outlineVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: done
                            ? successColor
                            : active
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurfaceVariant,
                        fontWeight:
                            active ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
