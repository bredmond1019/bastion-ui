/// `LaunchSheet` — the launch sheet: repo + workflow type + spec slug, one
/// primary action (`BU.12.E` task 4).
///
/// **Explicitly NOT a port** of bastion-web's `quick-launch.tsx` (750
/// lines) or `advanced-policy.tsx` (301 lines): no profile selector, no
/// policy panel, no effective-config readout, no request preview. Three
/// inputs and nothing else — adding any of that here is the failure mode
/// this block is scoped against (`planning/BU.12.E/tasks.md`, Out of
/// Scope).
///
/// ## Two validation layers, one authoritative
///
/// Client-side validation refuses to submit with an empty repo or spec
/// slug — a fast local check, not a substitute for the server's
/// `SDLC_FLOW` pre-flight. The server's answer is authoritative: it runs
/// BEFORE a run id is minted (`tasks.md` Notes), so a rejected launch
/// leaves nothing behind and correcting-and-retrying in place is the
/// natural interaction. On any `422` this sheet stays OPEN, marks the
/// offending field, and renders the server's own message — never a
/// generic failure banner, since the whole value of the pre-flight is
/// telling the operator which field is wrong.
///
/// ## Registry-sourced workflow types, never hardcoded
///
/// The workflow-type dropdown is driven entirely by
/// `state/engine_workflows_provider.dart`'s live `GET /workflows`
/// registry (task 3). [EngineWorkflowsLoading] disables the field with a
/// spinner, [EngineWorkflowsUnavailable] disables it with a reason, and an
/// empty [EngineWorkflowsLoaded] list disables it with "nothing
/// registered" — three distinguishable causes, never a silently-empty
/// dropdown.
///
/// ## Client ownership
///
/// [LaunchSheet] takes an already-constructed, already-probed-available
/// [EngineApi] from its caller (mirroring `runs_screen.dart`'s
/// `_RunDetailBodyState._engine` pattern) and never disposes it — the
/// caller (task 5's runs-list entry point) owns that lifecycle. Rule 7:
/// the engine key never appears in rendered text, a thrown error, or a
/// `toString()` anywhere in this file — every message shown either comes
/// from the server's own JSON body or is a literal string this file
/// wrote.
///
/// **Brand rule:** composed from `widgets/brand/` (`Eyebrow`) and
/// `AppTokens`/`StatusTones` only — no new colour token, no raw
/// `ListTile`, no hardcoded hex.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/bastion_api.dart' show ApiError, FatalAuthError;
import '../services/engine_api.dart';
import '../state/engine_workflows_provider.dart';
import '../state/runs_provider.dart';
import '../theme/status_tones.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/brand/brand.dart';

/// Presents [LaunchSheet] as a modal bottom sheet.
///
/// Resolves the new run id on a successful (`202`) launch, or `null` on
/// any dismissal — scrim tap, system back, or the sheet's own close
/// affordance — mirroring [showConfirmSheet]'s `?? null`-safe contract.
Future<String?> showLaunchSheet(
  BuildContext context, {
  required EngineApi engine,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => LaunchSheet(engine: engine),
  );
}

/// The launch sheet body: repo + workflow type + spec slug, one primary
/// action. See this file's doc comment for the full design rationale.
class LaunchSheet extends ConsumerStatefulWidget {
  const LaunchSheet({super.key, required this.engine});

  /// The engine client to launch through. Owned by the caller — never
  /// disposed here.
  final EngineApi engine;

  @override
  ConsumerState<LaunchSheet> createState() => _LaunchSheetState();
}

class _LaunchSheetState extends ConsumerState<LaunchSheet> {
  final _formKey = GlobalKey<FormState>();
  final _repoController = TextEditingController();
  final _specSlugController = TextEditingController();

  String? _selectedWorkflowType;
  bool _launching = false;

  /// Per-field server-side error text, populated from a `422`'s own
  /// message and cleared on the next edit to that field. Distinct from
  /// [Form]'s own client-side `validator` errors — these come from the
  /// server, not a local check, and survive re-validation until the
  /// operator actually changes the field.
  String? _repoServerError;
  String? _specSlugServerError;
  String? _workflowTypeServerError;

  /// A launch rejection that names no single field (`policy resolution
  /// failed`, `unresolvable target root`, or an unrecognised `422`) —
  /// rendered as a sheet-level banner rather than attached to any input.
  String? _generalError;

  @override
  void dispose() {
    _repoController.dispose();
    _specSlugController.dispose();
    super.dispose();
  }

  void _clearRepoError() {
    if (_repoServerError != null) {
      setState(() => _repoServerError = null);
    }
  }

  void _clearSpecSlugError() {
    if (_specSlugServerError != null) {
      setState(() => _specSlugServerError = null);
    }
  }

  String? _validateRepo(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Repo is required';
    }
    return null;
  }

  String? _validateSpecSlug(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Spec slug is required';
    }
    return null;
  }

  Future<void> _submit() async {
    final workflowType = _selectedWorkflowType;
    setState(() {
      _generalError = null;
    });
    final formOk = _formKey.currentState?.validate() ?? false;
    if (!formOk || workflowType == null) {
      if (workflowType == null) {
        setState(() {
          _workflowTypeServerError = 'Choose a workflow type';
        });
      }
      return;
    }

    setState(() => _launching = true);
    try {
      final outcome = await widget.engine.launchRun(
        workflowType: workflowType,
        data: {
          'repo': _repoController.text.trim(),
          'spec_slug': _specSlugController.text.trim(),
        },
      );
      if (!mounted) return;

      switch (outcome) {
        case LaunchAccepted(:final runId):
          // Refresh the runs list so the new run appears immediately,
          // then close and hand the run id to the caller. The messenger
          // is captured before the pop — after popping, `context` belongs
          // to whatever is behind this sheet.
          ref.invalidate(runsProvider);
          final messenger = ScaffoldMessenger.of(context);
          Navigator.of(context).pop(runId);
          messenger.showSnackBar(
            SnackBar(content: Text('Launched run $runId')),
          );
        case LaunchUnknownWorkflowType(:final workflowType):
          setState(() {
            _launching = false;
            _workflowTypeServerError = 'Unknown workflow type: $workflowType';
          });
        case LaunchUnknownRepo(:final repo, :final message):
          setState(() {
            _launching = false;
            _repoServerError = message ?? 'Unknown repo: $repo';
          });
        case LaunchUnknownSpecSlug(:final specSlug, :final message):
          setState(() {
            _launching = false;
            _specSlugServerError = message ?? 'Unknown spec slug: $specSlug';
          });
        case LaunchPolicyFailed(:final message):
          setState(() {
            _launching = false;
            _generalError = message ?? 'Policy resolution failed';
          });
        case LaunchUnresolvableTargetRoot(:final message):
          setState(() {
            _launching = false;
            _generalError = message ?? 'Unresolvable target root';
          });
        case LaunchUnknownRejection(:final rawBody):
          setState(() {
            _launching = false;
            _generalError = rawBody;
          });
      }
    } on FatalAuthError catch (_) {
      if (!mounted) return;
      setState(() {
        _launching = false;
        _generalError = 'The engine rejected the configured key.';
      });
    } on EngineNotConfiguredError catch (_) {
      if (!mounted) return;
      setState(() {
        _launching = false;
        _generalError = 'No engine key is configured.';
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _launching = false;
        _generalError = 'The server rejected this launch (${e.statusCode}).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _launching = false;
        // `e` here is only ever a network-layer exception
        // (SocketException/HttpException) — never anything carrying the
        // engine key (Rule 7, see `engine_api.dart`'s own guarantee).
        _generalError = 'Could not reach the server: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final workflowsState = ref.watch(engineWorkflowsProvider);

    return Container(
      key: const ValueKey('launch-sheet'),
      decoration: const BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTokens.radiusXxl),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(child: Eyebrow(label: 'Launch a run')),
                    IconButton(
                      key: const ValueKey('launch-sheet-close'),
                      icon: const Icon(Icons.close),
                      color: AppTokens.inkFaint,
                      tooltip: 'Close',
                      onPressed: _launching
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_generalError != null) ...[
                  _GeneralErrorBanner(message: _generalError!),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  key: const ValueKey('launch-sheet-repo-field'),
                  controller: _repoController,
                  enabled: !_launching,
                  style: AppTypography.textTheme.bodyMedium?.copyWith(
                    color: AppTokens.ink,
                  ),
                  decoration: _fieldDecoration(
                    labelText: 'Repo',
                    hintText: 'e.g. bastion-ui',
                    serverError: _repoServerError,
                  ),
                  autocorrect: false,
                  validator: _validateRepo,
                  onChanged: (_) => _clearRepoError(),
                ),
                const SizedBox(height: 16),
                _WorkflowTypeField(
                  state: workflowsState,
                  selected: _selectedWorkflowType,
                  enabled: !_launching,
                  serverError: _workflowTypeServerError,
                  onChanged: (value) => setState(() {
                    _selectedWorkflowType = value;
                    _workflowTypeServerError = null;
                  }),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('launch-sheet-spec-slug-field'),
                  controller: _specSlugController,
                  enabled: !_launching,
                  style: AppTypography.textTheme.bodyMedium?.copyWith(
                    color: AppTokens.ink,
                  ),
                  decoration: _fieldDecoration(
                    labelText: 'Spec slug',
                    hintText: 'e.g. BU.12.E',
                    serverError: _specSlugServerError,
                  ),
                  autocorrect: false,
                  validator: _validateSpecSlug,
                  onChanged: (_) => _clearSpecSlugError(),
                ),
                const SizedBox(height: 24),
                // One primary action — Launch is the single prominent
                // control on the sheet (Close, above, is a plain icon
                // button carrying none of the launch weight).
                FilledButton(
                  key: const ValueKey('launch-sheet-submit'),
                  onPressed: _launching ? null : _submit,
                  child: _launching
                      ? const SizedBox(
                          key: ValueKey('launch-sheet-spinner'),
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTokens.paper,
                          ),
                        )
                      : const Text('Launch'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A sheet-level banner for a launch rejection that names no single field
/// (`policy resolution failed` / `unresolvable target root` / an
/// unrecognised `422`'s raw body).
class _GeneralErrorBanner extends StatelessWidget {
  const _GeneralErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tones = context.statusTones;
    final danger = tones.danger;

    return Container(
      key: const ValueKey('launch-sheet-general-error'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: danger.background,
        border: Border.all(color: danger.border, width: 1),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Text(
        message,
        style: AppTypography.textTheme.bodySmall?.copyWith(
          color: danger.foreground,
        ),
      ),
    );
  }
}

/// The workflow-type picker: a dropdown sourced entirely from
/// [EngineWorkflowsState] (task 3's live-registry provider). Renders one
/// of four states — loading, unavailable-with-reason, empty-registry, or
/// a populated dropdown — never a silently-empty list.
class _WorkflowTypeField extends StatelessWidget {
  const _WorkflowTypeField({
    required this.state,
    required this.selected,
    required this.enabled,
    required this.serverError,
    required this.onChanged,
  });

  final EngineWorkflowsState state;
  final String? selected;
  final bool enabled;
  final String? serverError;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case EngineWorkflowsLoading():
        return const _WorkflowTypeStatus(
          key: ValueKey('launch-sheet-workflow-loading'),
          icon: Icons.hourglass_top,
          message: 'Loading workflow types…',
        );
      case EngineWorkflowsUnavailable(:final status):
        return _WorkflowTypeStatus(
          key: const ValueKey('launch-sheet-workflow-unavailable'),
          icon: Icons.error_outline,
          message: _unavailableReason(status),
          isError: true,
        );
      case EngineWorkflowsLoaded(:final types):
        if (types.isEmpty) {
          return const _WorkflowTypeStatus(
            key: ValueKey('launch-sheet-workflow-empty'),
            icon: Icons.info_outline,
            message: 'No workflow types are registered on this server.',
          );
        }
        final value = types.contains(selected) ? selected : null;
        return DropdownButtonFormField<String>(
          key: const ValueKey('launch-sheet-workflow-dropdown'),
          initialValue: value,
          isExpanded: true,
          items: [
            for (final type in types)
              DropdownMenuItem(value: type, child: Text(type)),
          ],
          onChanged: enabled ? onChanged : null,
          style: AppTypography.textTheme.bodyMedium?.copyWith(
            color: AppTokens.ink,
          ),
          dropdownColor: AppTokens.surfaceMuted,
          decoration: _fieldDecoration(
            labelText: 'Workflow type',
            serverError: serverError,
          ),
        );
    }
  }

  /// Distinguishes WHY the registry could not be read — the launch sheet
  /// gives an empty registry (nothing to launch, but the engine is fine)
  /// a different message from every unreachable-engine cause, per this
  /// file's doc comment.
  String _unavailableReason(EngineStatus status) {
    return switch (status) {
      EngineStatus.notConfigured =>
        'No engine key is configured — set one in Settings.',
      EngineStatus.notMounted => 'The engine is not mounted on this server.',
      EngineStatus.unauthorized => 'The engine rejected the configured key.',
      EngineStatus.unreachable => 'The engine could not be reached.',
      EngineStatus.available =>
        // Unreachable in practice — see EngineWorkflowsUnavailable's doc
        // comment: `available` always produces `EngineWorkflowsLoaded`
        // instead, even for an empty list.
        'The workflow registry could not be read.',
    };
  }
}

/// A single-line status row (loading / unavailable / empty) standing in
/// for the dropdown when [EngineWorkflowsState] is not
/// [EngineWorkflowsLoaded] with a non-empty list.
class _WorkflowTypeStatus extends StatelessWidget {
  const _WorkflowTypeStatus({
    super.key,
    required this.icon,
    required this.message,
    this.isError = false,
  });

  final IconData icon;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final tones = context.statusTones;
    final color = isError ? tones.danger.foreground : AppTokens.inkFaint;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppTokens.surfaceMuted,
        border: Border.all(color: AppTokens.line, width: 1),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTypography.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared field decoration for [LaunchSheet]'s text inputs, following
/// `settings_screen.dart`'s `_fieldDecoration` token treatment
/// ([AppTokens.surfaceMuted] fill, [AppTokens.line] hairline border,
/// [AppTokens.primary] on focus) with one addition: [serverError], which
/// — when set — renders in the [Form]'s own error slot via
/// [InputDecoration.errorText] so a server-side 422 message reads
/// identically to a client-side validator failure.
InputDecoration _fieldDecoration({
  required String labelText,
  String? hintText,
  String? serverError,
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
    borderSide: const BorderSide(color: AppTokens.line),
  );
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    errorText: serverError,
    filled: true,
    fillColor: AppTokens.surfaceMuted,
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: const BorderSide(color: AppTokens.primary, width: 2),
    ),
  );
}
