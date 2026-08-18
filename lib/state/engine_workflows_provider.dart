/// Riverpod state for the live workflow-type registry (`GET /workflows`),
/// backing the launch sheet's workflow-type picker (`BU.12.E` task 3).
///
/// ## Never hardcode workflow types
///
/// [EngineWorkflowsLoaded.types] is the ONLY source of workflow-type names
/// anywhere in the app — the engine registers types dynamically and this
/// list changes as it does (see `planning/BU.12.E/tasks.md` Notes: the live
/// mount returned 10 registered types on 2026-08-18, a number with no
/// business being compiled into the client).
///
/// ## Three states, not one list
///
/// A launch sheet that renders an empty dropdown whether the engine is
/// unconfigured, unmounted, or genuinely has nothing registered is
/// unusable — those are three different problems with three different
/// operator fixes (configure a key / start the server with engine env
/// vars / nothing to do here). [EngineWorkflowsState] is a sealed class
/// rather than a plain `List<String>` or an `AsyncValue` for exactly that
/// reason:
///   - [EngineWorkflowsLoading] — a probe/fetch is in flight.
///   - [EngineWorkflowsUnavailable] — the registry could not be read;
///     [EngineWorkflowsUnavailable.status] is the full five-way
///     [EngineStatus] (`notConfigured` / `notMounted` / `unauthorized` /
///     `unreachable`; `available` never appears here — that outcome always
///     produces [EngineWorkflowsLoaded] instead, even with zero types).
///   - [EngineWorkflowsLoaded] — the registry loaded. `types` may be
///     empty; that is a genuine "nothing registered" answer, distinct from
///     every [EngineWorkflowsUnavailable] reason.
///
/// ## Client construction — an injectable factory, not a shared provider
///
/// Unlike `bastionApiProvider`/`bastionSocketProvider` (set once by
/// `main.dart` after the bearer token loads), there is no shared
/// externally-set `EngineApi` provider in this app yet — `settings_screen.dart`
/// and `runs_screen.dart` each construct their own [EngineApi] ad hoc,
/// reading `connectionProvider` for host/port and
/// `ConnectionNotifier.readEngineKey()` for the key. This notifier follows
/// that same pattern (self-sufficient — no `main.dart` wiring required) but
/// builds its client through [engineApiFactoryProvider] rather than calling
/// the constructor directly, so a test can override the factory to hand
/// back an [EngineApi] wired to a fake transport instead of the real
/// `IoHttpTransport`.
///
/// Rule 7: the engine API key is read only to construct the client; it is
/// never placed in [EngineWorkflowsState], a log line, or an exception
/// message anywhere in this file (mirrors `engine_api.dart`'s own
/// guarantee).
///
/// This file is Flutter/riverpod-facing (not pure Dart) — it depends on
/// `services/engine_api.dart` and `state/connection_provider.dart`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/engine_api.dart';
import 'connection_provider.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// The state of the live workflow-type registry. See this file's doc
/// comment for why this is a three-member sealed class rather than a plain
/// list or an `AsyncValue`.
sealed class EngineWorkflowsState {
  const EngineWorkflowsState();
}

/// A probe/fetch is in flight — no answer yet, positive or negative.
final class EngineWorkflowsLoading extends EngineWorkflowsState {
  const EngineWorkflowsLoading();
}

/// The registry loaded. [types] is sorted (mirrors [EngineApi.getWorkflows])
/// and may be empty — a genuine "the engine has nothing registered" answer.
final class EngineWorkflowsLoaded extends EngineWorkflowsState {
  final List<String> types;
  const EngineWorkflowsLoaded(this.types);
}

/// The registry could not be read. [status] names why — see [EngineStatus]'s
/// five-way doc comment; this member never carries [EngineStatus.available]
/// (that outcome always produces [EngineWorkflowsLoaded], even for an empty
/// list). [error] carries a diagnostic string for the `unreachable` case
/// raised by an unexpected exception rather than [EngineApi.probeMount]
/// itself (which never throws); it is derived only from [Exception]
/// `toString()`s that this file's Rule-7 guarantee already covers, so it
/// can never contain the API key.
final class EngineWorkflowsUnavailable extends EngineWorkflowsState {
  final EngineStatus status;
  final String? error;
  const EngineWorkflowsUnavailable(this.status, {this.error});
}

// ---------------------------------------------------------------------------
// Client factory (the test injection seam)
// ---------------------------------------------------------------------------

/// Signature for constructing the [EngineApi] client this notifier probes.
typedef EngineApiFactory =
    EngineApi Function({
      required String host,
      required int port,
      required String? key,
    });

/// Builds the real [EngineApi] (default `IoHttpTransport`). Overridden in
/// tests to hand back a client wired to a fake transport instead.
final engineApiFactoryProvider = Provider<EngineApiFactory>(
  (ref) =>
      ({required String host, required int port, required String? key}) =>
          EngineApi(host: host, port: port, key: key),
);

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Live workflow-type registry: probes `GET /workflows` on first watch (and
/// on every [refresh]) via a fresh [EngineApi] built from the current
/// `connectionProvider` config + stored engine key.
final engineWorkflowsProvider =
    StateNotifierProvider<EngineWorkflowsNotifier, EngineWorkflowsState>((ref) {
      return EngineWorkflowsNotifier(ref);
    });

/// Owns the probe-then-fetch sequence for [engineWorkflowsProvider].
class EngineWorkflowsNotifier extends StateNotifier<EngineWorkflowsState> {
  EngineWorkflowsNotifier(this._ref) : super(const EngineWorkflowsLoading()) {
    refresh();
  }

  final Ref _ref;

  /// Re-probe the engine mount and, if available, re-fetch the registry.
  ///
  /// Always probes first (via [EngineApi.probeMount], which never throws)
  /// so `notConfigured`/`notMounted`/`unauthorized`/`unreachable` are
  /// reported with their real cause rather than collapsed into a generic
  /// fetch failure. Only an [EngineStatus.available] probe proceeds to
  /// [EngineApi.getWorkflows].
  Future<void> refresh() async {
    if (mounted) {
      state = const EngineWorkflowsLoading();
    }
    final config = _ref.read(connectionProvider).config;
    final key = await _ref.read(connectionProvider.notifier).readEngineKey();
    final factory = _ref.read(engineApiFactoryProvider);
    final engine = factory(host: config.host, port: config.port, key: key);
    try {
      final status = await engine.probeMount();
      if (status != EngineStatus.available) {
        if (mounted) {
          state = EngineWorkflowsUnavailable(status);
        }
        return;
      }
      final types = await engine.getWorkflows();
      if (mounted) {
        state = EngineWorkflowsLoaded(types);
      }
    } catch (e) {
      // getWorkflows can still throw after an `available` probe (e.g. a
      // transient network failure between the two calls, or a malformed
      // body) — degrade to unreachable rather than crash the provider tree.
      if (mounted) {
        state = EngineWorkflowsUnavailable(
          EngineStatus.unreachable,
          error: e.toString(),
        );
      }
    } finally {
      engine.dispose();
    }
  }
}
