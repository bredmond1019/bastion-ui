/// `ConfirmSheet` — reusable destructive-action confirmation sheet
/// (`BU.12.D` task 3).
///
/// A modal bottom sheet gating a destructive action (pause/resume never
/// confirm; abort does) behind an explicit choice. It always **names the
/// target** — the run id / spec slug the action would apply to — in its
/// body: a confirmation that does not say what it is confirming does not
/// prevent the mistake it exists to prevent.
///
/// Returns a `Future<bool>` so callers `await` an explicit confirmation.
/// Dismissing the sheet any way other than tapping the destructive action
/// — scrim tap, system back, or the Cancel button — resolves to `false`,
/// never `true`. [showConfirmSheet] enforces this even against
/// `showModalBottomSheet`'s own default of resolving `null` on a
/// non-explicit dismiss.
///
/// **Brand rule:** composed entirely from [PanelCard]-adjacent tokens —
/// [AppTokens] / [StatusTones] — plus [Eyebrow]. No new colour token, no
/// hardcoded hex, no raw `ListTile`. The destructive action is distinguished
/// from Cancel by weight, position, AND a leading severity stripe in the
/// danger tone — colour alone is never the only signal (design principle:
/// encode state in form).
library;

import 'package:flutter/material.dart';

import '../theme/status_tones.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'brand/eyebrow.dart';

/// Presents [ConfirmSheet] as a modal bottom sheet.
///
/// Resolves `true` only when the destructive action is tapped. Every other
/// dismissal path — scrim tap, system back, or the Cancel button — resolves
/// `false`. [showModalBottomSheet] itself resolves its future with `null`
/// on a bare dismiss (scrim/back), so the `?? false` here is load-bearing:
/// without it, a caller doing `if (await showConfirmSheet(...))` would
/// throw on a null unwrap, or — worse, if the caller instead wrote
/// `== true`-avoidant code — silently mistreat "dismissed" as something
/// other than "not confirmed".
Future<bool> showConfirmSheet(
  BuildContext context, {
  required String title,
  required String body,
  required String targetName,
  required String destructiveLabel,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => ConfirmSheet(
      title: title,
      body: body,
      targetName: targetName,
      destructiveLabel: destructiveLabel,
    ),
  );
  return result ?? false;
}

/// The confirmation sheet body: a title, a body naming [targetName], and a
/// Cancel / destructive action pair.
///
/// Exposed as a standalone widget (rather than only the [showConfirmSheet]
/// helper) so it is directly widget-testable.
class ConfirmSheet extends StatelessWidget {
  const ConfirmSheet({
    super.key,
    required this.title,
    required this.body,
    required this.targetName,
    required this.destructiveLabel,
  });

  /// The sheet's heading, rendered via [Eyebrow] (e.g. `"Abort run"`).
  final String title;

  /// The explanatory body text. Callers should compose [targetName] into
  /// this string themselves (e.g. `"This will abort run $targetName."`) —
  /// [ConfirmSheet] also renders [targetName] on its own line beneath so
  /// the target is never lost to word-wrap or a truncated body string.
  final String body;

  /// The name of the thing being acted on (run id / spec slug). Always
  /// rendered — a confirmation that does not say what it is confirming
  /// does not prevent the mistake it exists to prevent.
  final String targetName;

  /// The destructive action's button label (e.g. `"Abort"`).
  final String destructiveLabel;

  @override
  Widget build(BuildContext context) {
    final tones = context.statusTones;
    final danger = tones.danger;

    return Container(
      decoration: const BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTokens.radiusXxl),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Severity stripe on the leading edge — the destructive intent
          // is legible even with colour perception removed, matching the
          // SeverityRow convention elsewhere in the brand kit.
          Positioned(
            key: const ValueKey('confirm-sheet-stripe'),
            left: 0,
            top: 0,
            bottom: 0,
            width: 3,
            child: ColoredBox(color: danger.foreground),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: 16 + 3,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Eyebrow(label: title),
                  const SizedBox(height: 10),
                  Text(
                    body,
                    key: const Key('confirm-sheet-body'),
                    style: AppTypography.textTheme.bodyMedium?.copyWith(
                      color: AppTokens.inkSoft,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    key: const Key('confirm-sheet-target'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTokens.surfaceMuted,
                      border: Border.all(color: AppTokens.line, width: 1),
                      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                    ),
                    child: Text(
                      targetName,
                      style: AppTypography.mono.copyWith(color: AppTokens.ink),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('confirm-sheet-cancel'),
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          key: const Key('confirm-sheet-confirm'),
                          style: FilledButton.styleFrom(
                            backgroundColor: danger.foreground,
                            foregroundColor: AppTokens.paper,
                          ),
                          onPressed: () => Navigator.of(context).pop(true),
                          child: Text(
                            destructiveLabel,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
