/// Run DTOs mirroring `../bastion/docs/serve-api.md` §14 and
/// `../bastion/types/serve.ts` for `GET /api/runs` (`RunSummaryDto`) and
/// `GET /api/runs/{id}` (`RunStateDto` / `NodeTransitionDto` /
/// `RunUsageDto`).
///
/// This repo mirrors and pins the upstream contract, it never invents
/// (Standing Rule 6). Every optional wire field serializes as an absent key
/// when unset — this client treats "absent" and "explicit null" identically
/// and decodes both as Dart `null`, matching the convention already used by
/// `attention_dto.dart` / `board_dto.dart`.
///
/// This file is pure Dart — no Flutter or socket imports.
library;

// ---------------------------------------------------------------------------
// GET /api/runs -> RunSummaryDto[] (serve-api.md §14.1, v0.16 / v0.17 /
// v0.22)
// ---------------------------------------------------------------------------

/// One currently-tracked run, from `LiveStateStore::list_active()`.
///
/// `status` is decoded as a raw `String`, never an enum — an unrecognised
/// status (a future wire value this client does not yet know about) is
/// carried through verbatim rather than thrown on, the same degrade-not-
/// throw posture `frame.dart`'s unknown-`kind` handling and `board_dto.dart`'s
/// [UnknownBlockedByDto] use. `suspended` (v0.17) is a normal, LIVE status —
/// it is not lifecycle-terminal (see `run_transition.terminal`, serve-api
/// §8.3, mirrored on the WS layer in a later task of this block).
///
/// ```json
/// {
///   "run_id": "b6a1c1e0-0000-4000-8000-000000000000",
///   "status": "running",
///   "spec_slug": "11.T-run-summary-projection",
///   "started_at": "2026-07-24T12:00:00Z",
///   "updated_at": "2026-07-24T12:00:01Z"
/// }
/// ```
final class RunSummaryDto {
  /// The run's UUID as a string.
  final String runId;

  /// Workflow identity (e.g. `"sdlc-flow"`). **Always absent today** — no
  /// production code stamps a workflow-identity key anywhere `bastion` can
  /// read it from a live `TaskContext`; tracked by the engine-rs follow-up
  /// ticket `EN.ticket.expose-live-run-workflow-type`. Modelled as optional;
  /// this DTO never fabricates a default.
  final String? workflowType;

  /// Lowercase wire status: `pending`/`running`/`success`/`failed`/
  /// `cancelled`/`budget_halted`/`suspended` (v0.17), or any future value —
  /// carried through as-is (see class doc).
  final String status;

  /// The triggering event's `spec_slug` field, when present. Absent (not
  /// `null`) when the run's event carries no `spec_slug` key.
  final String? specSlug;

  /// Earliest non-null `node_runs[*].started_at` across all tracked nodes,
  /// as RFC3339. `null`/absent when the run has no recorded node
  /// transitions yet.
  final String? startedAt;

  /// Latest non-null `node_runs[*].started_at` or `completed_at` across all
  /// tracked nodes, as RFC3339. `null`/absent when the run has no recorded
  /// node transitions yet.
  final String? updatedAt;

  /// The repo that owns this run (v0.22), resolved by an exact `run_id`
  /// match against the registry's flow state. Absent (never `null`, never
  /// guessed) when no flow state carries this run's id, or when the request
  /// did not opt in via `?with_repo=1`.
  final String? repo;

  const RunSummaryDto({
    required this.runId,
    this.workflowType,
    required this.status,
    this.specSlug,
    this.startedAt,
    this.updatedAt,
    this.repo,
  });

  factory RunSummaryDto.fromJson(Map<String, dynamic> json) {
    return RunSummaryDto(
      runId: json['run_id'] as String? ?? '',
      workflowType: json['workflow_type'] as String?,
      status: json['status'] as String? ?? '',
      specSlug: json['spec_slug'] as String?,
      startedAt: json['started_at'] as String?,
      updatedAt: json['updated_at'] as String?,
      repo: json['repo'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'run_id': runId,
    if (workflowType != null) 'workflow_type': workflowType,
    'status': status,
    if (specSlug != null) 'spec_slug': specSlug,
    if (startedAt != null) 'started_at': startedAt,
    if (updatedAt != null) 'updated_at': updatedAt,
    if (repo != null) 'repo': repo,
  };
}

// ---------------------------------------------------------------------------
// GET /api/runs/{id} -> RunStateDto (serve-api.md §14.2)
// ---------------------------------------------------------------------------

/// One run's per-node snapshot — the `TaskContext` projected to wire shape.
///
/// **No aggregate status field exists here** — only per-node
/// [NodeTransitionDto.status] and the raw [metadata] blob. Do not invent an
/// aggregate; deriving one is a product decision this block has not been
/// given (see the block's task 1 description).
///
/// ```json
/// {
///   "run_id": "b6a1c1e0-0000-4000-8000-000000000000",
///   "event": {"ticket_id": "T-1"},
///   "metadata": {"workflow": "sdlc-flow"},
///   "nodes": [ ... ]
/// }
/// ```
final class RunStateDto {
  /// The run's UUID, echoed back.
  final String runId;

  /// The triggering event payload, carried through verbatim from
  /// `TaskContext::event`. Untyped — shape varies by workflow.
  final Object? event;

  /// Workflow-level metadata, carried through verbatim from
  /// `TaskContext::metadata`. May carry a `suspension` sub-object (v0.17).
  final Object? metadata;

  /// One entry per node class present in `TaskContext::node_runs`, sorted
  /// by class name. Empty when the run has no recorded node transitions
  /// yet.
  final List<NodeTransitionDto> nodes;

  const RunStateDto({
    required this.runId,
    this.event,
    this.metadata,
    required this.nodes,
  });

  factory RunStateDto.fromJson(Map<String, dynamic> json) {
    final rawNodes = json['nodes'];
    return RunStateDto(
      runId: json['run_id'] as String? ?? '',
      event: json['event'],
      metadata: json['metadata'],
      nodes: rawNodes is List
          ? rawNodes
                .whereType<Map<String, dynamic>>()
                .map(NodeTransitionDto.fromJson)
                .toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'run_id': runId,
    'event': event,
    'metadata': metadata,
    'nodes': nodes.map((n) => n.toJson()).toList(),
  };
}

/// One node's projected run state — the join of `TaskContext::node_runs
/// [class]` (status/timing/error/input/usage) with `TaskContext::nodes
/// [class]` (output), keyed by the node's class name.
///
/// `status` is decoded as a raw `String`, never an enum, for the same
/// degrade-not-throw reason documented on [RunSummaryDto.status]: an
/// unrecognised status must not throw.
///
/// ```json
/// {
///   "node": "DataIngestionNode",
///   "status": "success",
///   "started_at": "2026-07-24T12:00:00Z",
///   "completed_at": "2026-07-24T12:00:01Z",
///   "error": null,
///   "input": null,
///   "output": {"documents_loaded": 3},
///   "usage": null
/// }
/// ```
final class NodeTransitionDto {
  /// The node's class name — the map key in both `TaskContext::nodes` and
  /// `TaskContext::node_runs`.
  final String node;

  /// Lowercase wire status: `pending`/`running`/`success`/`failed`, or any
  /// future value — carried through as-is (see class doc).
  final String status;

  /// ISO-8601 UTC timestamp set on entry; `null`/absent while `pending`.
  final String? startedAt;

  /// ISO-8601 UTC timestamp set on success or failure; `null`/absent before
  /// completion.
  final String? completedAt;

  /// Error message; present only for a `failed` node.
  final String? error;

  /// The node's recorded input; present only for a `failed` node. Untyped —
  /// shape varies by node.
  final Object? input;

  /// The node's output from `TaskContext::nodes`; `null`/absent when not
  /// yet produced. Untyped — shape varies by node.
  final Object? output;

  /// Token/model usage; present only for LLM nodes.
  final RunUsageDto? usage;

  const NodeTransitionDto({
    required this.node,
    required this.status,
    this.startedAt,
    this.completedAt,
    this.error,
    this.input,
    this.output,
    this.usage,
  });

  factory NodeTransitionDto.fromJson(Map<String, dynamic> json) {
    final rawUsage = json['usage'];
    return NodeTransitionDto(
      node: json['node'] as String? ?? '',
      status: json['status'] as String? ?? '',
      startedAt: json['started_at'] as String?,
      completedAt: json['completed_at'] as String?,
      error: json['error'] as String?,
      input: json['input'],
      output: json['output'],
      usage: rawUsage is Map<String, dynamic>
          ? RunUsageDto.fromJson(rawUsage)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'node': node,
    'status': status,
    'started_at': startedAt,
    'completed_at': completedAt,
    'error': error,
    'input': input,
    'output': output,
    'usage': usage?.toJson(),
  };
}

/// Token/model usage for an LLM node (serve-api.md §14.2).
///
/// ```json
/// {"input_tokens": 512, "output_tokens": 128, "model": "claude-sonnet-5"}
/// ```
final class RunUsageDto {
  /// Prompt token count, when reported by the provider.
  final int? inputTokens;

  /// Completion token count, when reported by the provider.
  final int? outputTokens;

  /// Model identifier used for this node's LLM call.
  final String model;

  const RunUsageDto({this.inputTokens, this.outputTokens, required this.model});

  factory RunUsageDto.fromJson(Map<String, dynamic> json) {
    return RunUsageDto(
      inputTokens: (json['input_tokens'] as num?)?.toInt(),
      outputTokens: (json['output_tokens'] as num?)?.toInt(),
      model: json['model'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    if (inputTokens != null) 'input_tokens': inputTokens,
    if (outputTokens != null) 'output_tokens': outputTokens,
    'model': model,
  };
}
