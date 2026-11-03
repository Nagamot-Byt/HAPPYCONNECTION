import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:medlink_connect/features/ui/home_controller.dart';
import 'package:medlink_connect/features/ui/widgets/glass_container.dart';

class ConnectionLogsWidget extends StatelessWidget {
  const ConnectionLogsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HomeController>();
    final logs = controller.logEntries;
    final l10n = AppLocalizations.of(context)!;

    return GlassContainer(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  l10n.activityLogs,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton.outlined(
                  tooltip: l10n.clearLogs,
                  onPressed: logs.isEmpty ? null : controller.clearLogs,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: const Color(0xF20A1220),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.18),
                ),
              ),
              child: logs.isEmpty
                  ? Center(
                      child: Text(
                        l10n.noRecentActivity,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFFC3D0D9),
                            ),
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(8),
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final entry = logs[logs.length - 1 - index];
                        return Semantics(
                          label: entry.formatted,
                          child: ExcludeSemantics(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 2.0),
                              child: Text(
                                entry.formatted,
                                style: TextStyle(
                                  color: entry.isError
                                      ? const Color(0xFFFF9AA7)
                                      : const Color(0xFF7BF1B6),
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
