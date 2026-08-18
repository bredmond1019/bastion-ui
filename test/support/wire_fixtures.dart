// Wire-shaped fixtures for every route `BastionApi` consumes (BU.ticket.
// integration-test-tier task 2).
//
// Each fixture is a plain Dart `Map<String, dynamic>` (or `List`) shaped
// exactly like the JSON `bastion serve` emits for that route, so the
// integration tier (task 3+) can feed them through `FakeHttpTransport`
// without any file I/O in this layer.
//
// Provenance: every fixture below carries a comment naming the section of
// `../bastion/docs/serve-api.md` (v0.31, present in this checkout at the
// time this file was written) it mirrors, per the spec's declared-not-gated
// provenance requirement — see
// `planning/ticket-integration-test-tier/tasks.md`. Fixture fidelity to
// upstream is NOT gated by anything in this repo; that is the non-gating
// `e2e-serve-contract` check's job. A fixture that has drifted from the
// Dart model layer itself IS caught, by `wire_fixtures_test.dart` in this
// same directory, which decodes every fixture through its DTO.
//
// Per Standing Rule 6, these are copies of the upstream shape, never a
// local redefinition — a fixture disagreeing with upstream is a change
// request against `bastion`, not an edit here.
library;

// ---------------------------------------------------------------------------
// GET /health — serve-api.md §3
// ---------------------------------------------------------------------------

/// `HealthDto` — the only shape `/health` returns.
const Map<String, dynamic> healthFixture = {
  'status': 'ok',
  'service': 'bastion',
};

// ---------------------------------------------------------------------------
// Auth error — serve-api.md §2.2
// ---------------------------------------------------------------------------

/// `ErrorPayload` for a `401` response — every route's failure shape.
const Map<String, dynamic> unauthorizedErrorFixture = {
  'error': 'unauthorized',
  'code': 'unauthorized',
  'message': 'missing or invalid bearer token',
};

/// `ErrorPayload` for a `404`/`C002` "not found" response (e.g. an unknown
/// session, or a repo with no `handoff.md`).
const Map<String, dynamic> notFoundErrorFixture = {
  'error': 'not_found',
  'code': 'C002',
  'message': 'resource not found',
};

// ---------------------------------------------------------------------------
// GET /api/sessions — serve-api.md §10.1, §10.3 (SessionDto[])
// ---------------------------------------------------------------------------

/// Fully populated `SessionDto`, including the optional v0.31
/// `blocked_reason` sub-classification.
const Map<String, dynamic> sessionFullFixture = {
  'name': 'main',
  'state': 'running',
  'last_line': '\$ cargo test',
  'agent_state': 'blocked',
  'blocked_reason': 'awaiting_question',
};

/// Minimal `SessionDto` — every optional field absent.
const Map<String, dynamic> sessionMinimalFixture = {
  'name': 'idle-session',
  'state': 'idle',
};

/// `GET /api/sessions` empty-collection response.
const List<dynamic> sessionsEmptyFixture = [];

/// `GET /api/sessions` populated response.
const List<dynamic> sessionsFixture = [
  sessionFullFixture,
  sessionMinimalFixture,
];

// ---------------------------------------------------------------------------
// GET /api/sessions/{name}/pane — serve-api.md §10.1, §10.3 (PaneDto)
// ---------------------------------------------------------------------------

/// Fully populated `PaneDto`.
const Map<String, dynamic> paneFullFixture = {
  'session_name': 'main',
  'lines': ['\$ cargo test', 'running 12 tests', 'test result: ok'],
};

/// `PaneDto` with an empty pane (e.g. a freshly created session).
const Map<String, dynamic> paneEmptyFixture = {
  'session_name': 'fresh-session',
  'lines': <String>[],
};

// ---------------------------------------------------------------------------
// POST /api/sessions/{name}/send, /key, POST /api/sessions,
// DELETE /api/sessions/{name} — serve-api.md §10.3
// ---------------------------------------------------------------------------
//
// All four return `204 No Content` (send/key/delete) or `201 Created`
// (create) with no body `BastionApi` decodes — success is the status code
// alone. No response-body fixture is meaningful here.

// ---------------------------------------------------------------------------
// GET /api/repos — serve-api.md §11.1 (RepoSummaryDto[])
// ---------------------------------------------------------------------------

/// Fully populated `RepoSummaryDto`.
const Map<String, dynamic> repoSummaryFullFixture = {
  'name': 'bastion-ui',
  'now': 'wiring dashboard',
  'has_handoff': true,
};

/// Minimal `RepoSummaryDto` — the empty-frontmatter sentinel the server
/// emits for an unset `now:` field (repo_status_dto.dart's `_text` helper
/// blanks this).
const Map<String, dynamic> repoSummaryMinimalFixture = {
  'name': 'mev',
  'now': '[]',
  'has_handoff': false,
};

/// `GET /api/repos` empty-collection response (no registered workspaces).
const List<dynamic> reposEmptyFixture = [];

/// `GET /api/repos` populated response.
const List<dynamic> reposFixture = [
  repoSummaryFullFixture,
  repoSummaryMinimalFixture,
];

// ---------------------------------------------------------------------------
// GET /api/repos/{name}/status — serve-api.md §11.2 (RepoStatusDto)
// ---------------------------------------------------------------------------

/// Fully populated `RepoStatusDto`.
const Map<String, dynamic> repoStatusFullFixture = {
  'name': 'bastion-ui',
  'now': 'wiring dashboard',
  'next': 'repo detail',
  'blocked': 'waiting on serve-api v0.31',
  'has_handoff': true,
  'momentum_now': 'Task 2 in flight',
  'momentum_next': 'Task 3 queued',
  'momentum_blocked': '',
  'momentum_improve': 'tighten fixtures',
  'momentum_recurring': 'nightly validate',
};

/// Minimal `RepoStatusDto` — empty-frontmatter sentinels on every text
/// field (the shape the server emits when a repo's `status.md` has no
/// content for a section).
const Map<String, dynamic> repoStatusMinimalFixture = {
  'name': 'mev',
  'now': '[]',
  'next': '[]',
  'blocked': '[]',
  'has_handoff': false,
  'momentum_now': '',
  'momentum_next': '',
  'momentum_blocked': '',
  'momentum_improve': '',
  'momentum_recurring': '',
};

// ---------------------------------------------------------------------------
// GET /api/repos/{name}/handoff — serve-api.md §11.3 (HandoffInfo)
// ---------------------------------------------------------------------------

/// Fully populated `HandoffInfo`.
const Map<String, dynamic> handoffFullFixture = {
  'title': 'Handoff — BU.ticket.integration-test-tier',
  'body': '## Summary\n\nTask 2 landed the wire fixtures.',
};

// A repo with no `handoff.md` responds `404` with `notFoundErrorFixture`
// (code `C002`), decoded by `getRepoHandoff` as `null` rather than thrown —
// see `notFoundErrorFixture` above; no separate "empty" HandoffInfo shape
// exists on the wire.

// ---------------------------------------------------------------------------
// GET /api/repos/{name}/workflows — serve-api.md §11.4 (WorkflowStateDto[])
// ---------------------------------------------------------------------------

/// Fully populated `WorkflowStateDto`.
const Map<String, dynamic> workflowFullFixture = {
  'spec_slug': '2.A-dashboard-repo-detail',
  'branch': '2.A-dashboard-repo-detail-flow',
  'status': 'running',
  'current_task': 5,
  'started_at': '2026-07-02T10:00:00Z',
  'updated_at': '2026-07-02T10:15:00Z',
};

/// `GET /api/repos/{name}/workflows` empty-collection response (no
/// in-flight or completed workflows for this repo).
const List<dynamic> workflowsEmptyFixture = [];

/// `GET /api/repos/{name}/workflows` populated response.
const List<dynamic> workflowsFixture = [workflowFullFixture];

// ---------------------------------------------------------------------------
// POST /api/actions/command — serve-api.md §12.1
// (CommandRequest request body / CommandResponse response body)
// ---------------------------------------------------------------------------

/// A `mode: "inject"` request body.
const Map<String, dynamic> commandInjectRequestFixture = {
  'mode': 'inject',
  'session': 'main',
  'command': '/status',
};

/// A `mode: "spawn"` request body with every optional field populated.
const Map<String, dynamic> commandSpawnRequestFixture = {
  'mode': 'spawn',
  'name': 'work',
  'dir': '/repo',
  'model': 'opus',
  'command': '/status',
};

/// `CommandResponse` — the only response shape, for either mode.
const Map<String, dynamic> commandResponseFixture = {'session': 'work'};

// ---------------------------------------------------------------------------
// GET /api/board — serve-api.md §13.3 (BoardDto)
// ---------------------------------------------------------------------------

/// A single `BoardBlockDto` with one of each `BlockedByDto` variant plus an
/// unrecognised one, and the `?graph=true` enrichment fields populated.
const Map<String, dynamic> boardBlockFullFixture = {
  'id': 'BA.11.K',
  'title': 'Cross-brain board read endpoint',
  'repo': 'bastion',
  'status': 'in_progress',
  'blocked_by': [
    {'type': 'block', 'repo': 'mev', 'id': 'MV.1.A', 'what': 'parser'},
    {'type': 'external', 'what': 'upstream API key'},
    {
      'type': 'operator',
      'slug': 'BU.ticket.review',
      'exit': 'decision recorded',
      'start': '2026-08-01',
      'what': 'operator sign-off',
    },
    {
      'type': 'approval',
      'slug': 'BU.ticket.deploy',
      'what': 'production push',
      'digest': 'abc123',
    },
    {'type': 'future_variant', 'note': 'not yet a known BlockedBy shape'},
  ],
  'epics': ['bastion-surfaces'],
  'wave': 3,
  'priority': 1,
  'due': '2026-07-15',
  'track': 'Phase 11',
  'dependent_count': 2,
  'ready': true,
  'unmet_count': 0,
  'last_touched': '2026-08-10T12:00:00Z',
  'effective_priority': 1,
  'description': 'Cross-brain board read endpoint, full description.',
  'created': '2026-06-01',
  'closed': '2026-08-05',
  'commit': 'abc123def',
  'origin': {'kind': 'carryover', 'slug': 'BU.carryover.board-drift'},
};

/// Minimal `BoardBlockDto` — every optional field, including `blocked_by`,
/// the `?graph=true`-only fields, and `last_touched`, absent. `last_touched`
/// absent means "never worked" — not merely "unrequested" like the
/// `?graph=true` fields.
const Map<String, dynamic> boardBlockMinimalFixture = {
  'id': 'BA.1.A',
  'title': 'Bootstrap',
  'repo': 'bastion',
};

/// A `BoardLaneDto` with every lane populated.
const Map<String, dynamic> boardLaneFullFixture = {
  'now': [boardBlockFullFixture],
  'next': [boardBlockMinimalFixture],
  'blocked': <dynamic>[],
  'deferred': <dynamic>[],
  'finished': <dynamic>[],
};

/// A `BoardLaneDto` with every lane absent (defaults to empty).
const Map<String, dynamic> boardLaneEmptyFixture = {};

/// `GET /api/board?scope=hq` response — aggregate only, no per-repo
/// breakdown.
const Map<String, dynamic> boardHqFixture = {
  'scope': 'hq',
  'lanes': boardLaneFullFixture,
  'stale': false,
};

/// `GET /api/board?scope=project` response — includes the per-repo
/// `repos[]` breakdown (`RepoBoardDto`).
const Map<String, dynamic> boardProjectFixture = {
  'scope': 'project',
  'lanes': boardLaneFullFixture,
  'repos': [
    {'repo': 'bastion-ui', 'tier': 'core', 'lanes': boardLaneEmptyFixture},
  ],
  'stale': true,
};

/// Empty board response — no in-scope blocks at all.
const Map<String, dynamic> boardEmptyFixture = {
  'lanes': boardLaneEmptyFixture,
  'repos': <dynamic>[],
  'stale': false,
};

// ---------------------------------------------------------------------------
// GET /api/lanes — serve-api.md §28.2 (LanesDto, v0.35, BA.19.C)
// ---------------------------------------------------------------------------

/// A single `LaneSegmentDto` in `startable` state — every field populated.
const Map<String, dynamic> laneSegmentStartableFixture = {
  'roadmap': 'engine-orchestration',
  'lane': 'derive',
  'segment': 0,
  'repo': 'mev',
  'head': 'mev:MV.13.C',
  'availability': 'startable',
  'leverage_lanes_freed': 2,
};

/// A `done` `LaneSegmentDto` — `head`/`reason` absent, matching the
/// contract's "absent, not null" rule for a segment with no frontier entry.
const Map<String, dynamic> laneSegmentDoneFixture = {
  'roadmap': 'engine-orchestration',
  'lane': 'derive',
  'segment': 1,
  'repo': 'mev',
  'availability': 'done',
  'leverage_lanes_freed': 0,
};

/// A `held-block` `LaneSegmentDto` — `reason` populated.
const Map<String, dynamic> laneSegmentHeldFixture = {
  'roadmap': 'engine-orchestration',
  'lane': 'transform',
  'segment': 0,
  'repo': 'engine-rs',
  'head': 'engine-rs:EN.4.A',
  'availability': 'held-block',
  'reason': 'waiting on mev:MV.13.C',
  'leverage_lanes_freed': 0,
};

/// `GET /api/lanes` response — fleet-wide, no `?epic=` filter.
const Map<String, dynamic> lanesFixture = {
  'derived_at': '2026-08-18T10:00:00-07:00',
  'degraded': false,
  'segments': [
    laneSegmentStartableFixture,
    laneSegmentDoneFixture,
    laneSegmentHeldFixture,
  ],
};

/// `GET /api/lanes?epic=<slug>` response with a known-but-unmatched slug —
/// an empty `segments` array is a real answer, not an error.
const Map<String, dynamic> lanesEmptyFixture = {
  'derived_at': '2026-08-18T10:00:00-07:00',
  'degraded': false,
  'segments': <dynamic>[],
};

// ---------------------------------------------------------------------------
// GET /api/attention — serve-api.md §15.3 (AttentionDto)
// ---------------------------------------------------------------------------

/// Fully populated `AttentionCarryoverDto`.
const Map<String, dynamic> attentionCarryoverFullFixture = {
  'repo': 'bastion-ui',
  'slug': 'BU.ticket.integration-test-tier',
  'kind': 'known_issue',
  'text': 'six duplicated FakeHttpTransport copies',
  'clears_when': 'task 6 lands',
  'created': '2026-08-01',
  'reviewed': '2026-08-10',
  'age_days': 13,
  'threshold_days': 10,
  'lane': 'hot',
  'priority': 2,
  'effective_priority': 1,
  'unmet_blocks': ['BU.ticket.other'],
  'finding_id': 'F-001',
  'clears_when_satisfied': false,
};

/// Minimal `AttentionCarryoverDto` — every optional field absent, and
/// `age_days` explicitly `null` (a snoozed/anchor-less entry — see the
/// DTO's doc comment: `null` must never be treated as `0`).
const Map<String, dynamic> attentionCarryoverMinimalFixture = {
  'repo': 'mev',
  'slug': 'MV.ticket.snoozed',
  'kind': 'env',
  'text': 'snoozed entry',
  'threshold_days': 30,
  'lane': 'standing',
  'clears_when_satisfied': false,
};

/// Fully populated `AttentionBacklogDto`.
const Map<String, dynamic> attentionBacklogFullFixture = {
  'repo': 'bastion-ui',
  'slug': 'idea-slug',
  'title': 'An aging idea',
  'kind': 'feature',
  'status': 'idea',
  'notes': 'came up in a retro',
  'created': '2026-06-01',
  'reviewed': '2026-06-15',
  'age_days': 60,
  'threshold_days': 45,
};

/// Minimal `AttentionBacklogDto` — every optional field absent.
const Map<String, dynamic> attentionBacklogMinimalFixture = {
  'repo': 'mev',
  'slug': 'orphaned-slug',
  'title': 'An orphaned capture',
  'kind': 'capture',
  'status': 'ready',
  'age_days': 90,
  'threshold_days': 45,
};

/// `AttentionThresholdsDto` — always fully populated (all five are `u32`
/// on the wire, per `brain.toml [attention]`, D67).
const Map<String, dynamic> attentionThresholdsFixture = {
  'env_days': 14,
  'deferred_days': 21,
  'known_issue_days': 10,
  'constraint_days': 30,
  'backlog_days': 45,
};

/// `GET /api/attention` populated response.
const Map<String, dynamic> attentionFixture = {
  'scope': 'hq',
  'as_of': '2026-08-14',
  'lanes': {
    'stale_carryover': [
      attentionCarryoverFullFixture,
      attentionCarryoverMinimalFixture,
    ],
    'aging_backlog': [attentionBacklogFullFixture],
    'orphaned_captures': [attentionBacklogMinimalFixture],
  },
  'thresholds': attentionThresholdsFixture,
};

/// `GET /api/attention` empty-collection response — all three lanes empty.
const Map<String, dynamic> attentionEmptyFixture = {
  'as_of': '2026-08-14',
  'lanes': <String, dynamic>{},
  'thresholds': attentionThresholdsFixture,
};

// ---------------------------------------------------------------------------
// GET /api/docs/{repo}/tree — serve-api.md §16.1 (DocTreeDto)
// ---------------------------------------------------------------------------

/// Fully populated `DocEntryDto` pair (one dir, one file).
const Map<String, dynamic> docEntryDirFixture = {
  'path': 'planning',
  'name': 'planning',
  'is_dir': true,
};

const Map<String, dynamic> docEntryFileFixture = {
  'path': 'planning/status.md',
  'name': 'status.md',
  'is_dir': false,
};

/// Fully populated `DocTreeDto`.
const Map<String, dynamic> docTreeFullFixture = {
  'repo': 'bastion-ui',
  'root': '',
  'entries': [docEntryDirFixture, docEntryFileFixture],
};

/// `DocTreeDto` with no markdown-bearing entries under the requested root.
const Map<String, dynamic> docTreeEmptyFixture = {
  'repo': 'bastion-ui',
  'root': 'empty-dir',
  'entries': <dynamic>[],
};

// ---------------------------------------------------------------------------
// GET /api/runs — serve-api.md §14.1 (RunSummaryDto[], v0.16/v0.17/v0.22)
// ---------------------------------------------------------------------------

/// Fully populated `RunSummaryDto`, including the v0.22 `repo` enrichment.
/// `workflow_type` is deliberately omitted — always absent today per
/// serve-api §14.1's field table.
const Map<String, dynamic> runSummaryFullFixture = {
  'run_id': 'b6a1c1e0-0000-4000-8000-000000000000',
  'status': 'running',
  'spec_slug': '11.T-run-summary-projection',
  'started_at': '2026-07-24T12:00:00Z',
  'updated_at': '2026-07-24T12:00:01Z',
  'repo': 'bastion-ui',
};

/// Minimal `RunSummaryDto` — every optional field, including `workflow_type`,
/// absent; `started_at`/`updated_at` explicit `null` (no recorded node
/// transitions yet, per the serve-api §14.1 worked example's second entry).
const Map<String, dynamic> runSummaryMinimalFixture = {
  'run_id': 'c7b2d2f1-0000-4000-8000-000000000000',
  'status': 'pending',
  'started_at': null,
  'updated_at': null,
};

/// A `RunSummaryDto` with the v0.17 `suspended` status — LIVE, not
/// lifecycle-terminal.
const Map<String, dynamic> runSummarySuspendedFixture = {
  'run_id': 'd8c3e3a2-0000-4000-8000-000000000000',
  'status': 'suspended',
  'spec_slug': '11.N-run-transition-ws-push',
  'started_at': '2026-08-01T10:00:00Z',
  'updated_at': '2026-08-01T10:05:00Z',
};

/// `GET /api/runs` empty-collection response — a valid, expected success,
/// including when no engine is mounted.
const List<dynamic> runsEmptyFixture = [];

/// `GET /api/runs` populated response.
const List<dynamic> runsFixture = [
  runSummaryFullFixture,
  runSummaryMinimalFixture,
  runSummarySuspendedFixture,
];

// ---------------------------------------------------------------------------
// GET /api/runs/{id} — serve-api.md §14.2 (RunStateDto)
// ---------------------------------------------------------------------------

/// Fully populated `NodeTransitionDto` for a successful node.
const Map<String, dynamic> nodeTransitionSuccessFixture = {
  'node': 'DataIngestionNode',
  'status': 'success',
  'started_at': '2026-07-24T12:00:00Z',
  'completed_at': '2026-07-24T12:00:01Z',
  'error': null,
  'input': null,
  'output': {'documents_loaded': 3},
  'usage': null,
};

/// A `NodeTransitionDto` for a failed LLM node, with `error`/`input`/`usage`
/// all populated.
const Map<String, dynamic> nodeTransitionFailedFixture = {
  'node': 'SummarizeNode',
  'status': 'failed',
  'started_at': '2026-07-24T12:00:01Z',
  'completed_at': '2026-07-24T12:00:02Z',
  'error': 'timeout',
  'input': {'documents': 3},
  'output': null,
  'usage': {
    'input_tokens': 512,
    'output_tokens': 128,
    'model': 'claude-sonnet-5',
  },
};

/// Minimal `NodeTransitionDto` — still `pending`, every optional field
/// absent.
const Map<String, dynamic> nodeTransitionPendingFixture = {
  'node': 'PendingNode',
  'status': 'pending',
};

/// Fully populated `RunStateDto` — no aggregate status field, per §14.2.
const Map<String, dynamic> runStateFullFixture = {
  'run_id': 'b6a1c1e0-0000-4000-8000-000000000000',
  'event': {'ticket_id': 'T-1'},
  'metadata': {'workflow': 'sdlc-flow'},
  'nodes': [nodeTransitionSuccessFixture, nodeTransitionFailedFixture],
};

/// `RunStateDto` for a run with no recorded node transitions yet.
const Map<String, dynamic> runStateEmptyFixture = {
  'run_id': 'c7b2d2f1-0000-4000-8000-000000000000',
  'event': <String, dynamic>{},
  'metadata': <String, dynamic>{},
  'nodes': <dynamic>[],
};

// ---------------------------------------------------------------------------
// GET /api/docs/{repo}/file — serve-api.md §16.2 (DocFileDto)
// ---------------------------------------------------------------------------

/// Fully populated `DocFileDto`.
const Map<String, dynamic> docFileFullFixture = {
  'repo': 'bastion-ui',
  'path': 'planning/status.md',
  'content': '# Status\n\nOn track.\n',
  'bytes': 20,
  'modified': '2026-08-14T09:00:00Z',
};

/// Minimal `DocFileDto` — `modified` absent (filesystem mtime unavailable),
/// empty file content.
const Map<String, dynamic> docFileMinimalFixture = {
  'repo': 'bastion-ui',
  'path': 'planning/empty.md',
  'content': '',
  'bytes': 0,
};
