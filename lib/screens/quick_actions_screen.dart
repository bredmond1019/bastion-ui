/// Quick-actions screen — the command palette itself.
///
/// Lists the user-editable entries from [commandsProvider]; tapping one
/// opens [CommandInvokeSheet] (inject/spawn chooser). Add / edit / delete
/// affordances route through [CommandsNotifier] so changes persist. When
/// the sheet returns a server-assigned session id, navigates to that
/// session's pane via the existing [sessionDetailRouteName] route.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/commands_provider.dart';
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
      body: commands.isEmpty
          ? const Center(child: Text('No commands yet'))
          : ListView.builder(
              itemCount: commands.length,
              itemBuilder: (context, index) {
                final entry = commands[index];
                return ListTile(
                  key: ValueKey('command-tile-${entry.label}-$index'),
                  title: Text(entry.label),
                  subtitle: Text(entry.command),
                  onTap: () => _fire(context, ref, entry.command),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: Key('command-edit-$index'),
                        icon: const Icon(Icons.edit),
                        onPressed: () => _showEditDialog(
                          context,
                          ref,
                          index: index,
                          entry: entry,
                        ),
                      ),
                      IconButton(
                        key: Key('command-delete-$index'),
                        icon: const Icon(Icons.delete),
                        onPressed: () =>
                            ref.read(commandsProvider.notifier).delete(index),
                      ),
                    ],
                  ),
                );
              },
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
