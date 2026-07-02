/// Riverpod state for the dashboard's workspace-registry repo list.
///
/// [reposProvider] seeds the list via a one-shot REST `GET /api/repos` call
/// (through [bastionApiProvider], shared with `sessions_provider.dart`) and
/// exposes a [RepoSummaryDto] list plus a [RepoListNotifier.refresh] method
/// for pull-to-refresh — the repo list itself has no WS push (only per-repo
/// `workflow_done` events do; see `workflows_provider.dart`), so a manual
/// refresh is the only way to pick up a newly-registered repo.
///
/// This file is Flutter/riverpod-facing (not pure Dart) — it depends on
/// `services/bastion_api.dart`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/repo_status_dto.dart';
import '../services/bastion_api.dart';
import 'sessions_provider.dart' show bastionApiProvider;

/// Live list of workspace-registry repos: REST-seeded on first read, with a
/// manual [RepoListNotifier.refresh] for pull-to-refresh.
final reposProvider =
    StateNotifierProvider<RepoListNotifier, List<RepoSummaryDto>>((ref) {
      final api = ref.watch(bastionApiProvider);
      if (api == null) {
        throw StateError(
          'reposProvider read before bastionApiProvider was set — the app '
          'shell must connect before mounting the dashboard.',
        );
      }
      // NB: StateNotifierProvider disposes the returned notifier
      // automatically when the provider itself is disposed — do not also
      // register `ref.onDispose(notifier.dispose)` here, or dispose() runs
      // twice.
      return RepoListNotifier(api);
    });

/// Owns the one-shot `GET /api/repos` seed (and manual refresh) for
/// [reposProvider].
class RepoListNotifier extends StateNotifier<List<RepoSummaryDto>> {
  RepoListNotifier(this._api) : super(const []) {
    refresh();
  }

  final BastionApi _api;

  /// Re-fetch the repo list from `GET /api/repos`.
  ///
  /// Failures are non-fatal — the previous state is left in place (the
  /// caller may surface the error separately, e.g. via a snackbar); this
  /// keeps the dashboard resilient to a transient network blip during
  /// pull-to-refresh.
  Future<void> refresh() async {
    try {
      final repos = await _api.getRepos();
      if (mounted) {
        state = repos;
      }
    } catch (_) {
      // Non-fatal: keep the previously-seeded list.
    }
  }
}
