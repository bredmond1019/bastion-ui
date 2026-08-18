/// Runs screen — live workflow runs, pushed over the `runs` WS topic
/// (`BU.13.E` task 5).
///
/// Watches `state/runs_provider.dart`'s [runsProvider] (REST-seeded,
/// WS-live `List<RunSummaryDto>`) and renders one row per run. Tapping a
/// row drills into that run's per-node snapshot (`GET /api/runs/{id}` via
/// [BastionApi.getRun]) as a VERTICAL node list only — a DAG view is
/// unreadable at phone width and is explicitly out of scope for this block
/// (see `planning/13.E-live-runs/tasks.md`).
///
/// ## Trap 2, made visible: `suspended` reads as live-but-paused
///
/// `run_transition.terminal` is lifecycle-terminal, the OPPOSITE of the
/// engine's own wire-terminal flag (serve-api.md §8.3/§14) — a suspended
/// run reports `status: "suspended", terminal: false` and stays in
/// [runsProvider]'s list. [_RunStatusVisual] gives every wire status both a
/// [StatusTones] tone AND a distinct [IconData] (a non-colour channel), so
/// a suspended run never reads as finished even in grayscale: `suspended`
/// renders in the same live `active` tone as `running`, with a pause icon
/// instead of a play icon, while every finished status (`success`/
/// `failed`/`cancelled`/`budget_halted`) renders in a settled tone with a
/// settled icon.
///
/// ## Trap 3, made visible: `200 []` is a valid empty state
///
/// When the server has no engine mounted, `GET /api/runs` returns `200 []`
/// forever — [_RunsListBody] renders a real, explanatory empty state for an
/// empty list, never an error and never an endless spinner.
///
/// This screen composes the instrument kit (`widgets/instrument/`) and
/// brand primitives only — no new colour tokens.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/run_dto.dart';
import '../services/bastion_api.dart';
import '../services/engine_api.dart';
import '../state/connection_provider.dart' hide ConnectionState;
import '../state/runs_provider.dart';
import '../state/sessions_provider.dart' show bastionApiProvider;
import '../theme/status_tones.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/brand/brand.dart';
import '../widgets/confirm_sheet.dart';
import '../widgets/instrument/instrument.dart';
import 'launch_sheet.dart';

/// The tone + icon + label a wire `status` string renders with, resolved
/// once per row so both the run list and the node-drill-in view render
/// identically for the same status value.
class _RunStatusVisual {
  const _RunStatusVisual({
    required this.tone,
    required this.icon,
    required this.label,
    required this.isLive,
  });

  final StatusTone tone;
  final IconData icon;
  final String label;

  /// True for every non-finished status, including `suspended` — see this
  /// file's doc comment, trap 2.
  final bool isLive;

  /// Resolves [status] (a raw wire string — see [RunSummaryDto.status]'s
  /// doc comment on why this is never an enum) to its visual.
  ///
  /// An unrecognised status degrades to a neutral, live-looking badge
  /// carrying the raw text uppercased, rather than throwing — the same
  /// degrade-not-throw posture the DTO layer already uses.
  factory _RunStatusVisual.of(String status, StatusTones tones) {
    switch (status) {
      case 'pending':
        return _RunStatusVisual(
          tone: tones.neutral,
          icon: Icons.schedule,
          label: 'PENDING',
          isLive: true,
        );
      case 'running':
        return _RunStatusVisual(
          tone: tones.active,
          icon: Icons.play_circle_fill,
          label: 'RUNNING',
          isLive: true,
        );
      case 'suspended':
        return _RunStatusVisual(
          tone: tones.active,
          icon: Icons.pause_circle_filled,
          label: 'SUSPENDED',
          isLive: true,
        );
      case 'success':
        return _RunStatusVisual(
          tone: tones.success,
          icon: Icons.check_circle,
          label: 'SUCCESS',
          isLive: false,
        );
      case 'failed':
        return _RunStatusVisual(
          tone: tones.danger,
          icon: Icons.error,
          label: 'FAILED',
          isLive: false,
        );
      case 'cancelled':
        return _RunStatusVisual(
          tone: tones.neutral,
          icon: Icons.block,
          label: 'CANCELLED',
          isLive: false,
        );
      case 'budget_halted':
        return _RunStatusVisual(
          tone: tones.warning,
          icon: Icons.warning_amber,
          label: 'HALTED',
          isLive: false,
        );
      default:
        return _RunStatusVisual(
          tone: tones.neutral,
          icon: Icons.help_outline,
          label: status.isEmpty ? 'UNKNOWN' : status.toUpperCase(),
          isLive: true,
        );
    }
  }
}

/// A small tone+icon+label badge for a run or node status, built from
/// [_RunStatusVisual]. Deliberately not [StatusPill] — [StatusPill] is
/// fixed to four UI-affordance tones (on-track/needs-you/blocked/
/// in-progress) that do not map onto the run/node status vocabulary; this
/// badge draws directly from the ambient [StatusTones] six-tone palette
/// instead, introducing no new colour tokens.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final tones = context.statusTones;
    final visual = _RunStatusVisual.of(status, tones);

    final style = TextStyle(
      fontFamily: AppTypography.mono.fontFamily,
      fontWeight: AppTypography.mono.fontWeight,
      fontSize: AppTypography.textTheme.labelSmall?.fontSize ?? 11,
      color: visual.tone.foreground,
      letterSpacing: 0.6,
    );

    return Container(
      key: ValueKey('status-badge-${status.isEmpty ? 'unknown' : status}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: visual.tone.background,
        border: Border.all(color: visual.tone.border, width: 1),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(visual.icon, size: 13, color: visual.tone.foreground),
          const SizedBox(width: 4),
          Text(visual.label, style: style),
        ],
      ),
    );
  }
}

/// Live runs list — REST-seeded and kept current by the `runs` WS topic
/// (`state/runs_provider.dart`). Tapping a run drills into its per-node
/// snapshot; the app bar's back affordance returns to the list.
class RunsScreen extends ConsumerStatefulWidget {
  const RunsScreen({super.key});

  @override
  ConsumerState<RunsScreen> createState() => _RunsScreenState();
}

class _RunsScreenState extends ConsumerState<RunsScreen> {
  /// Captured once, not read from the wall clock inside `build` — feeds
  /// every [AgeChip.since] call on this screen and its drill-in view, per
  /// the pattern `briefing_screen.dart`/`dashboard_screen.dart` already
  /// use.
  late final DateTime _now;

  /// The run currently drilled into, or `null` for the list view.
  String? _selectedRunId;

  /// The engine client backing the launch entry point (`BU.12.E` task 5),
  /// built once the engine key + connection config have been read from
  /// secure storage — same lazy-init pattern as
  /// `_RunDetailBodyState._initEngine`. `null` until that read resolves.
  EngineApi? _launchEngine;

  /// Result of the mount probe run against [_launchEngine], or `null`
  /// while the probe is still in flight. Feeds
  /// [_LaunchEntryPoint._disabledReason] so "no key configured" and
  /// "engine not mounted" read as distinct causes rather than one generic
  /// disabled control.
  EngineStatus? _launchEngineStatus;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _initLaunchEngine();
  }

  Future<void> _initLaunchEngine() async {
    final config = ref.read(connectionProvider).config;
    final key = await ref.read(connectionProvider.notifier).readEngineKey();
    if (!mounted) return;
    final engine = EngineApi(host: config.host, port: config.port, key: key);
    final status = await engine.probeMount();
    if (!mounted) {
      engine.dispose();
      return;
    }
    setState(() {
      _launchEngine = engine;
      _launchEngineStatus = status;
    });
  }

  @override
  void dispose() {
    _launchEngine?.dispose();
    super.dispose();
  }

  void _open(String runId) => setState(() => _selectedRunId = runId);

  void _closeDetail() => setState(() => _selectedRunId = null);

  Future<void> _launch() async {
    final engine = _launchEngine;
    if (engine == null) return;
    await showLaunchSheet(context, engine: engine);
    // The runs list is WS-live (`runsProvider`) — a successful launch's
    // new run arrives on the `runs` topic without a manual refetch here.
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedRunId;
    final runs = ref.watch(runsProvider);

    if (selected != null) {
      RunSummaryDto? match;
      for (final run in runs) {
        if (run.runId == selected) {
          match = run;
          break;
        }
      }
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const ValueKey('runs-detail-back'),
            icon: const Icon(Icons.arrow_back),
            onPressed: _closeDetail,
          ),
          title: const Text('Run'),
        ),
        body: _RunDetailBody(
          runId: selected,
          api: ref.watch(bastionApiProvider)!,
          now: _now,
          runStatus: match?.status,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Runs')),
      body: _RunsListBody(
        runs: runs,
        now: _now,
        onTap: _open,
        launchEngineStatus: _launchEngineStatus,
        onLaunch: _launch,
      ),
    );
  }
}

/// The runs-list body: a header row ([Eyebrow] plus the launch entry
/// point, `BU.12.E` task 5), then either the no-engine/no-runs empty
/// state or the scrolling list of run rows.
class _RunsListBody extends StatelessWidget {
  const _RunsListBody({
    required this.runs,
    required this.now,
    required this.onTap,
    required this.launchEngineStatus,
    required this.onLaunch,
  });

  final List<RunSummaryDto> runs;
  final DateTime now;
  final void Function(String runId) onTap;

  /// Drives [_LaunchEntryPoint]'s enabled/disabled state and reason.
  final EngineStatus? launchEngineStatus;
  final VoidCallback onLaunch;

  @override
  Widget build(BuildContext context) {
    final sorted = [...runs]..sort((a, b) => a.runId.compareTo(b.runId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(child: Eyebrow(label: 'Runs')),
              _LaunchEntryPoint(status: launchEngineStatus, onLaunch: onLaunch),
            ],
          ),
        ),
        Expanded(
          child: sorted.isEmpty
              ? const _RunsEmptyState()
              : ListView.builder(
                  key: const ValueKey('runs-list'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  itemCount: sorted.length,
                  itemBuilder: (context, index) {
                    final run = sorted[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _RunRow(
                        key: ValueKey('run-row-${run.runId}'),
                        run: run,
                        now: now,
                        onTap: () => onTap(run.runId),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// The launch entry point on the runs list header (`BU.12.E` task 5) —
/// deliberately a small text-and-icon control, not a [FilledButton], so it
/// never out-weighs the run rows the way [_RunControlRow]'s Pause/Resume/
/// Abort row is allowed to (that row IS the primary content of the run
/// detail screen; here launching is secondary to "what is running").
///
/// **Disabled with a visible reason, not hidden** whenever
/// [EngineStatus.available] is not reached — reusing the same
/// `EngineStatus` mount probe [_RunControlRow] uses so "no key configured"
/// and "engine not mounted" render as distinguishable reasons rather than
/// one generic disabled state.
class _LaunchEntryPoint extends StatelessWidget {
  const _LaunchEntryPoint({required this.status, required this.onLaunch});

  final EngineStatus? status;
  final VoidCallback onLaunch;

  bool get _enabled => status == EngineStatus.available;

  /// The visible reason the entry point is disabled, or `null` when the
  /// engine is available. Every [EngineStatus] member gets its own
  /// distinguishable reason string — mirrors
  /// `_RunControlRowState._engineDisabledReason`.
  String? get _disabledReason {
    switch (status) {
      case null:
        return 'Checking engine status…';
      case EngineStatus.notConfigured:
        return 'No engine key configured — set one in Settings.';
      case EngineStatus.notMounted:
        return 'Engine not mounted on this server.';
      case EngineStatus.unauthorized:
        return 'Engine key was rejected.';
      case EngineStatus.unreachable:
        return 'Engine unreachable.';
      case EngineStatus.available:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reason = _disabledReason;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        TextButton.icon(
          key: const ValueKey('runs-launch-entry'),
          onPressed: _enabled ? onLaunch : null,
          style: TextButton.styleFrom(
            foregroundColor: AppTokens.accent2,
            disabledForegroundColor: AppTokens.inkFaint,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            visualDensity: VisualDensity.compact,
          ),
          icon: const Icon(Icons.add_circle_outline, size: 18),
          label: const Text('Launch'),
        ),
        if (reason != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              reason,
              key: const ValueKey('runs-launch-disabled-reason'),
              style: AppTypography.textTheme.bodySmall?.copyWith(
                color: AppTokens.inkFaint,
              ),
              textAlign: TextAlign.right,
            ),
          ),
      ],
    );
  }
}

/// Real, explanatory empty state for `GET /api/runs` returning `200 []` —
/// which is always either "no engine mounted" or "nothing running right
/// now", never an error and never a reason to spin forever (trap 3).
class _RunsEmptyState extends StatelessWidget {
  const _RunsEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: const ValueKey('runs-empty-state'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timeline_outlined, size: 32, color: AppTokens.inkFaint),
            const SizedBox(height: 12),
            Text(
              'No live runs',
              style: AppTypography.textTheme.titleSmall?.copyWith(
                color: AppTokens.ink,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Nothing is running right now, or this server has no engine '
              'mounted. A run started elsewhere appears here as soon as it '
              'starts.',
              style: AppTypography.textTheme.bodySmall?.copyWith(
                color: AppTokens.inkFaint,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// One run row in the list: a [SeverityRow] carrying the run's status
/// badge and age, tappable to drill in.
///
/// The tap affordance itself (the trailing chevron) renders in
/// [AppTokens.accent2] — the same colour token [StatusTones.active] is
/// built from — but is kept separable from the `active`/"running" status
/// signal by shape, not colour: the status is a filled icon inside a
/// bordered pill ([_StatusBadge]), the tap affordance is a bare outline
/// chevron glyph in a fixed neutral position, so the two never read as the
/// same signal even when both happen to render in the same hue.
class _RunRow extends StatelessWidget {
  const _RunRow({super.key, required this.run, required this.now, this.onTap});

  final RunSummaryDto run;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final updatedAt = DateTime.tryParse(run.updatedAt ?? '');
    final metaParts = <String>[
      if (run.specSlug != null && run.specSlug!.isNotEmpty) run.specSlug!,
      run.workflowType ?? 'workflow type pending',
    ];

    return InkWell(
      key: const ValueKey('run-row-tap'),
      borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTokens.surface,
          border: Border.all(color: AppTokens.line, width: 1),
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    run.runId,
                    style: AppTypography.textTheme.titleSmall?.copyWith(
                      color: AppTokens.ink,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    metaParts.join(' · '),
                    style: AppTypography.textTheme.bodySmall?.copyWith(
                      color: AppTokens.inkFaint,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _StatusBadge(status: run.status),
                      const SizedBox(width: 8),
                      if (updatedAt != null) AgeChip.since(updatedAt, now: now),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              key: const ValueKey('run-row-chevron'),
              color: AppTokens.accent2,
            ),
          ],
        ),
      ),
    );
  }
}

/// The drill-in body for one run: fetches `GET /api/runs/{id}` and renders
/// its [NodeTransitionDto]s as a VERTICAL list — never a DAG (out of
/// scope, unreadable at phone width; see this file's doc comment) — plus
/// (`BU.12.D`) a pause/resume/abort control row above the node list.
class _RunDetailBody extends ConsumerStatefulWidget {
  const _RunDetailBody({
    required this.runId,
    required this.api,
    required this.now,
    this.runStatus,
  });

  final String runId;
  final BastionApi api;
  final DateTime now;

  /// The run's current wire status, sourced from the live `runsProvider`
  /// list this screen already watches — `null` when the run has already
  /// scrolled out of that list (e.g. reached via a deep link) or its
  /// status is not yet known. [_RunControlRow] treats `null` as "not
  /// knowable client-side" and leaves pause/resume enabled, letting the
  /// route's own 409 answer rather than inventing client state the server
  /// owns.
  final String? runStatus;

  @override
  ConsumerState<_RunDetailBody> createState() => _RunDetailBodyState();
}

class _RunDetailBodyState extends ConsumerState<_RunDetailBody> {
  late Future<RunStateDto> _future;

  /// The engine client for this run's controls, built once the engine key
  /// + connection config have been read from secure storage. `null` until
  /// that read resolves.
  EngineApi? _engine;

  /// Result of the mount probe run against [_engine], or `null` while the
  /// probe is still in flight.
  EngineStatus? _engineStatus;

  @override
  void initState() {
    super.initState();
    _future = widget.api.getRun(widget.runId);
    _initEngine();
  }

  Future<void> _initEngine() async {
    final config = ref.read(connectionProvider).config;
    final key = await ref.read(connectionProvider.notifier).readEngineKey();
    if (!mounted) return;
    final engine = EngineApi(host: config.host, port: config.port, key: key);
    final status = await engine.probeMount();
    if (!mounted) {
      engine.dispose();
      return;
    }
    setState(() {
      _engine = engine;
      _engineStatus = status;
    });
  }

  @override
  void dispose() {
    _engine?.dispose();
    super.dispose();
  }

  /// Re-fetches the run's node-transition snapshot. Passed to
  /// [_RunControlRow] as the "re-read the run" step after a `202` — a
  /// control action never mutates local state optimistically, it only
  /// triggers a fresh read (see `_RunControlRow`'s doc comment).
  void _reload() {
    setState(() {
      _future = widget.api.getRun(widget.runId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: _RunControlRow(
            runId: widget.runId,
            engine: _engine,
            engineStatus: _engineStatus,
            runStatus: widget.runStatus,
            onReload: _reload,
          ),
        ),
        Expanded(
          child: FutureBuilder<RunStateDto>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  key: ValueKey('run-detail-loading'),
                  child: CircularProgressIndicator(),
                );
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      key: const ValueKey('run-detail-error'),
                      'Could not load this run: ${snapshot.error}',
                      style: AppTypography.textTheme.bodyMedium?.copyWith(
                        color: AppTokens.inkFaint,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              final run = snapshot.data!;
              if (run.nodes.isEmpty) {
                return Center(
                  child: Text(
                    key: const ValueKey('run-detail-no-nodes'),
                    'No node transitions recorded yet for this run.',
                    style: AppTypography.textTheme.bodyMedium?.copyWith(
                      color: AppTokens.inkFaint,
                    ),
                    textAlign: TextAlign.center,
                  ),
                );
              }

              return ListView.builder(
                key: const ValueKey('run-node-list'),
                padding: const EdgeInsets.all(16),
                itemCount: run.nodes.length,
                itemBuilder: (context, index) {
                  final node = run.nodes[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _NodeRow(
                      key: ValueKey('node-row-${node.node}'),
                      node: node,
                      now: widget.now,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Pause / resume / abort control row for one run (`BU.12.D` task 5).
///
/// - Disabled — with the reason rendered, never hidden — whenever the
///   engine is not [EngineStatus.available] (no key configured, engine not
///   mounted, key rejected, or unreachable). Hiding the row would make a
///   configuration problem look like a missing feature.
/// - Abort routes through [showConfirmSheet] naming [runId]; pause and
///   resume fire immediately.
/// - A `202` is rendered as its in-flight verb (pausing/resuming/aborting)
///   and triggers [onReload] — it is never treated as an achieved state.
///   The run's real status comes from the next read (here, and from the
///   live `runsProvider` list), never from a local optimistic mutation.
/// - Every other typed outcome (409/404/422) renders its own
///   operator-readable message, verbatim from the server where one exists.
class _RunControlRow extends StatefulWidget {
  const _RunControlRow({
    required this.runId,
    required this.engine,
    required this.engineStatus,
    required this.runStatus,
    required this.onReload,
  });

  final String runId;
  final EngineApi? engine;
  final EngineStatus? engineStatus;
  final String? runStatus;
  final VoidCallback onReload;

  @override
  State<_RunControlRow> createState() => _RunControlRowState();
}

class _RunControlRowState extends State<_RunControlRow> {
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  bool get _engineAvailable =>
      widget.engine != null && widget.engineStatus == EngineStatus.available;

  /// The visible reason the whole row is disabled, or `null` when the
  /// engine itself is available (per-action disablement below still
  /// applies on top of this). Every [EngineStatus] member gets its own
  /// distinguishable reason string.
  String? get _engineDisabledReason {
    switch (widget.engineStatus) {
      case null:
        return 'Checking engine status…';
      case EngineStatus.notConfigured:
        return 'No engine key configured — set one in Settings.';
      case EngineStatus.notMounted:
        return 'Engine not mounted on this server.';
      case EngineStatus.unauthorized:
        return 'Engine key was rejected.';
      case EngineStatus.unreachable:
        return 'Engine unreachable.';
      case EngineStatus.available:
        return null;
    }
  }

  /// Pause is meaningless on a run already known to be suspended. When the
  /// run's status is not knowable client-side ([widget.runStatus] is
  /// `null`), the action is left enabled and the route's own `409`
  /// answers instead of this widget inventing server-owned state.
  bool get _canPause =>
      _engineAvailable && !_busy && widget.runStatus != 'suspended';

  /// Resume is meaningless on a run that is not suspended. Same
  /// "unknowable → leave enabled" rule as [_canPause].
  bool get _canResume =>
      _engineAvailable &&
      !_busy &&
      (widget.runStatus == null || widget.runStatus == 'suspended');

  bool get _canAbort => _engineAvailable && !_busy;

  void _setMessage(String message, {required bool isError}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = isError;
    });
  }

  /// Maps a thrown error to an operator-readable message. Never includes
  /// the API key — [ApiError.body] and [FatalAuthError.payload] both
  /// originate from the SERVER's response, not from anything this client
  /// sent, so neither can echo the key back (Rule 7).
  void _handleError(Object error) {
    if (error is FatalAuthError) {
      _setMessage('Engine key was rejected.', isError: true);
    } else if (error is EngineNotConfiguredError) {
      _setMessage('No engine key configured.', isError: true);
    } else if (error is ApiError) {
      _setMessage(
        'Unexpected response from the engine (status ${error.statusCode}).',
        isError: true,
      );
    } else if (error is SocketException || error is HttpException) {
      _setMessage('Could not reach the engine.', isError: true);
    } else {
      _setMessage('Something went wrong.', isError: true);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pause() => _run(() async {
    try {
      final outcome = await widget.engine!.pauseRun(widget.runId);
      switch (outcome) {
        case PausePausing():
          _setMessage('Pausing…', isError: false);
          widget.onReload();
        case PauseAlreadySuspended(:final error):
          _setMessage(error, isError: true);
        case PauseNotFound(:final error):
          _setMessage(error, isError: true);
      }
    } catch (e) {
      _handleError(e);
    }
  });

  Future<void> _resume() => _run(() async {
    try {
      final outcome = await widget.engine!.resumeRun(widget.runId);
      switch (outcome) {
        case ResumeResuming():
          _setMessage('Resuming…', isError: false);
          widget.onReload();
        case ResumeAlreadyResuming(:final error):
          _setMessage(error, isError: true);
        case ResumeNotFound(:final error):
          _setMessage(error, isError: true);
        case ResumePolicyFailed(:final error, :final message):
          _setMessage(message ?? error, isError: true);
      }
    } catch (e) {
      _handleError(e);
    }
  });

  Future<void> _abortConfirmed() => _run(() async {
    try {
      final outcome = await widget.engine!.abortRun(widget.runId);
      switch (outcome) {
        case AbortAborting():
          _setMessage('Aborting…', isError: false);
          widget.onReload();
        case AbortNotFound(:final error):
          _setMessage(error, isError: true);
      }
    } catch (e) {
      _handleError(e);
    }
  });

  Future<void> _abort() async {
    final confirmed = await showConfirmSheet(
      context,
      title: 'Abort run',
      body: 'This will abort run ${widget.runId}. This cannot be undone.',
      targetName: widget.runId,
      destructiveLabel: 'Abort',
    );
    if (!confirmed) return;
    await _abortConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.statusTones;
    final disabledReason = _engineDisabledReason;

    return PanelCard(
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Eyebrow(label: 'Controls'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('run-control-pause'),
                    onPressed: _canPause ? _pause : null,
                    child: const Text('Pause'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('run-control-resume'),
                    onPressed: _canResume ? _resume : null,
                    child: const Text('Resume'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('run-control-abort'),
                    style: FilledButton.styleFrom(
                      backgroundColor: tones.danger.foreground,
                      foregroundColor: AppTokens.paper,
                    ),
                    onPressed: _canAbort ? _abort : null,
                    child: const Text(
                      'Abort',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
            if (disabledReason != null) ...[
              const SizedBox(height: 8),
              Text(
                disabledReason,
                key: const ValueKey('run-control-disabled-reason'),
                style: AppTypography.textTheme.bodySmall?.copyWith(
                  color: AppTokens.inkFaint,
                ),
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(
                _message!,
                key: const ValueKey('run-control-message'),
                style: AppTypography.textTheme.bodySmall?.copyWith(
                  color: _messageIsError
                      ? tones.danger.foreground
                      : AppTokens.inkFaint,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One node's row in the vertical node list: name, status badge, and
/// timing — the same [_StatusBadge] the run-list rows use, so a node's
/// status reads with the identical tone/icon vocabulary as its parent
/// run's status.
class _NodeRow extends StatelessWidget {
  const _NodeRow({super.key, required this.node, required this.now});

  final NodeTransitionDto node;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final completedAt = DateTime.tryParse(node.completedAt ?? '');
    final startedAt = DateTime.tryParse(node.startedAt ?? '');
    final ageAnchor = completedAt ?? startedAt;

    return Container(
      decoration: BoxDecoration(
        color: AppTokens.surface,
        border: Border.all(color: AppTokens.line, width: 1),
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  node.node,
                  style: AppTypography.textTheme.titleSmall?.copyWith(
                    color: AppTokens.ink,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _StatusBadge(status: node.status),
            ],
          ),
          if (ageAnchor != null) ...[
            const SizedBox(height: 8),
            AgeChip.since(ageAnchor, now: now),
          ],
          if (node.error != null && node.error!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              node.error!,
              style: AppTypography.textTheme.bodySmall?.copyWith(
                color: context.statusTones.danger.foreground,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
