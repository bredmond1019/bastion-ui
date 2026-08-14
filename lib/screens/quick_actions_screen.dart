/// Quick-actions screen — the command palette itself.
///
/// Lists the user-editable entries from [commandsProvider]; tapping one
/// opens [CommandInvokeSheet] (inject/spawn chooser). Add / edit / delete
/// affordances route through [CommandsNotifier] so changes persist. When
/// the sheet returns a server-assigned session id, navigates to that
/// session's pane via the existing [sessionDetailRouteName] route.
///
/// Re-skinned in `BU.10.C` task 5: the screen wears a display heading with
/// a [HeadingRule] underneath (budget rule: one per screen), and each
/// palette entry is now a [PanelCard] wearing a [GradientTopBar] whose hue
/// cycles by list index (`hueForIndex`, the same cadence
/// `dashboard_screen.dart` uses) and an [IconTile] glyph.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/commands_provider.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/brand/brand.dart';
import '../widgets/command_invoke_sheet.dart';
import 'sessions_list_screen.dart' show sessionDetailRouteName;

/// The command-palette screen: list, add, edit, delete, and fire palette
/// entries.
class QuickActionsScreen extends ConsumerWidget {
  const QuickActionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commands = ref.watch(commandsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Quick Actions')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: _QuickActionsHeading(),
          ),
          Expanded(
            child: commands.isEmpty
                ? Center(
                    child: Text(
                      'No commands yet',
                      style: AppTypography.textTheme.bodyMedium?.copyWith(
                        color: AppTokens.inkFaint,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: commands.length,
                    itemBuilder: (context, index) {
                      final entry = commands[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: PanelCard(
                          child: InkWell(
                            key: ValueKey('command-tile-${entry.label}-$index'),
                            onTap: () => _fire(context, ref, entry.command),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Budget rule: one gradient bar per panel.
                                GradientTopBar(hue: hueForIndex(index)),
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      const IconTile(
                                        icon: Icons.bolt_outlined,
                                        accent: IconAccent.accent2,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              entry.label,
                                              overflow: TextOverflow.ellipsis,
                                              style: AppTypography
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                    color: AppTokens.ink,
                                                  ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              entry.command,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: AppTypography.mono
                                                  .copyWith(
                                                    color: AppTokens.inkSoft,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        key: Key('command-edit-$index'),
                                        icon: const Icon(
                                          Icons.edit,
                                          color: AppTokens.inkSoft,
                                        ),
                                        onPressed: () => _showEditDialog(
                                          context,
                                          ref,
                                          index: index,
                                          entry: entry,
                                        ),
                                      ),
                                      IconButton(
                                        key: Key('command-delete-$index'),
                                        icon: const Icon(
                                          Icons.delete,
                                          color: AppTokens.destructive,
                                        ),
                                        onPressed: () => ref
                                            .read(commandsProvider.notifier)
                                            .delete(index),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('command-add-button'),
        onPressed: () => _showEditDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  /// Open the invoke sheet for [command]; on success, navigate to the
  /// server-returned session id.
  Future<void> _fire(
    BuildContext context,
    WidgetRef ref,
    String command,
  ) async {
    final sessionId = await showCommandInvokeSheet(context, command: command);
    if (sessionId == null) return;
    if (!context.mounted) return;
    Navigator.of(context).pushNamed(sessionDetailRouteName(sessionId));
  }

  /// Show the add/edit dialog. When [index]/[entry] are provided, edits
  /// that entry in place; otherwise appends a new one.
  Future<void> _showEditDialog(
    BuildContext context,
    WidgetRef ref, {
    int? index,
    PaletteCommand? entry,
  }) async {
    final labelController = TextEditingController(text: entry?.label ?? '');
    final commandController = TextEditingController(text: entry?.command ?? '');
    final isEdit = index != null;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isEdit ? 'Edit command' : 'Add command'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('command-dialog-label'),
              controller: labelController,
              decoration: const InputDecoration(labelText: 'Label'),
            ),
            TextField(
              key: const Key('command-dialog-command'),
              controller: commandController,
              decoration: const InputDecoration(labelText: 'Command'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('command-dialog-save'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != true) return;

    final label = labelController.text.trim();
    final command = commandController.text.trim();
    if (label.isEmpty || command.isEmpty) return;

    final notifier = ref.read(commandsProvider.notifier);
    final newEntry = PaletteCommand(label: label, command: command);
    if (isEdit) {
      await notifier.update(index, newEntry);
    } else {
      await notifier.add(newEntry);
    }
  }
}

/// This screen's display heading — one [HeadingRule] underneath, per the
/// block's budget rule (one per screen).
class _QuickActionsHeading extends StatelessWidget {
  const _QuickActionsHeading();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Command Palette',
          style: AppTypography.textTheme.headlineSmall?.copyWith(
            color: AppTokens.ink,
          ),
        ),
        const SizedBox(height: 8),
        const HeadingRule(),
      ],
    );
  }
}
