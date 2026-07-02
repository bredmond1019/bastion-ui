/// Quick-approve button row for the session-detail screen.
///
/// Renders one button per common "unblock a waiting prompt" keystroke —
/// `y` / `Enter` / `Esc` / `1` / `2` — and sends it to [sessionName] via
/// `bastion_api.dart`'s v0.1 session REST routes ([BastionApi.sendKeys] for
/// literal characters that should be followed by `Enter`, [BastionApi.sendKey]
/// for symbolic tmux key names).
///
/// Reads [bastionApiProvider] directly (rather than taking the API as a
/// constructor argument) so the row can be dropped into any screen that
/// already sits inside the app's [ProviderScope] — mirrors how
/// `sessions_list_screen.dart` reads its providers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/bastion_api.dart';
import '../state/sessions_provider.dart' show bastionApiProvider;

/// One quick-approve button definition.
class ApproveKey {
  const ApproveKey({required this.label, required this.send});

  /// Button label (also used as the [Key] label in tests).
  final String label;

  /// Sends this key to [api] for [sessionName].
  final Future<void> Function(BastionApi api, String sessionName) send;
}

/// The fixed set of quick-approve keys, in display order.
///
/// Public so widget tests can drive/assert against the same definitions
/// this row renders from.
const List<ApproveKey> approveKeys = [
  ApproveKey(label: 'y', send: _sendY),
  ApproveKey(label: 'Enter', send: _sendEnter),
  ApproveKey(label: 'Esc', send: _sendEsc),
  ApproveKey(label: '1', send: _sendOne),
  ApproveKey(label: '2', send: _sendTwo),
];

Future<void> _sendY(BastionApi api, String sessionName) =>
    api.sendKeys(sessionName, 'y');
Future<void> _sendEnter(BastionApi api, String sessionName) =>
    api.sendKey(sessionName, 'Enter');
Future<void> _sendEsc(BastionApi api, String sessionName) =>
    api.sendKey(sessionName, 'Escape');
Future<void> _sendOne(BastionApi api, String sessionName) =>
    api.sendKeys(sessionName, '1');
Future<void> _sendTwo(BastionApi api, String sessionName) =>
    api.sendKeys(sessionName, '2');

/// A row of quick-approve buttons for [sessionName].
class ApproveButtonRow extends ConsumerWidget {
  const ApproveButtonRow({super.key, required this.sessionName});

  /// The session the quick-approve buttons act on.
  final String sessionName;

  Future<void> _handleTap(
    BuildContext context,
    WidgetRef ref,
    ApproveKey approveKey,
  ) async {
    final api = ref.read(bastionApiProvider);
    try {
      await approveKey.send(api, sessionName);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send "${approveKey.label}": $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final approveKey in approveKeys)
            OutlinedButton(
              key: ValueKey('approve-${approveKey.label}'),
              onPressed: () => _handleTap(context, ref, approveKey),
              child: Text(approveKey.label),
            ),
        ],
      ),
    );
  }
}
