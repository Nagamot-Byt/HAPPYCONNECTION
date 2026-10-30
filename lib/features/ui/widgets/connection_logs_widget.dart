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
    final logs = controller.logs;
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
                color: Colors.black.withAlpha(76),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withAlpha(25)),
              ),
              child: logs.isEmpty
                  ? Center(
                      child: Text(
                        l10n.noRecentActivity,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(8),
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final line = logs[logs.length - 1 - index];
                        final isErr = line.contains('❌');
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Text(
                            line,
                            style: TextStyle(
                              color:
                                  isErr ? Colors.redAccent : Colors.greenAccent,
                              fontFamily: 'monospace',
                              fontSize: 12,
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
