/// Local notification wrapper for BastionUI's single alert use case: telling
/// the operator a session is blocked waiting on input (serve-api v0.2
/// `event{needs_input}`).
///
/// [NotificationService] is a thin wrapper around
/// `flutter_local_notifications` — `initialize()` sets up the platform
/// channel once at app startup, `notifyNeedsInput(sessionName)` fires a
/// single local notification for that session.
///
/// [notificationServiceProvider] is the riverpod injection point: `main.dart`
/// creates and initializes one [NotificationService] at startup and overrides
/// this provider with it (mirrors the `bastionSocketProvider`/
/// `bastionApiProvider` pattern in `state/sessions_provider.dart`), except a
/// default value is provided here (rather than throwing) so screens/tests
/// that don't care about notifications don't need to override it.
///
/// [notificationWiringProvider] bridges `state/events_provider.dart`'s
/// [needsInputEventsProvider] to [NotificationService.notifyNeedsInput] — it
/// must be `watch`n somewhere live in the widget tree (e.g. the app root)
/// for the subscription to be created; merely defining the provider does not
/// activate it.
///
/// [notifyWorkflowDone]/[workflowDoneNotificationWiringProvider] mirror the
/// above for `state/workflows_provider.dart`'s `workflowDoneEventsProvider`
/// (serve-api v0.3 §8.2 `workflow_done` event) — a second, independent
/// notification channel so a workflow-done alert never replaces (or is
/// replaced by) an unrelated needs-input alert.
library;

import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/frame.dart';
import '../state/events_provider.dart';
import '../state/workflows_provider.dart';

/// Android notification channel used for all needs-input alerts.
const _needsInputChannelId = 'needs_input';
const _needsInputChannelName = 'Needs Input';
const _needsInputChannelDescription =
    'Alerts when a session is blocked waiting for operator input.';

/// Android notification channel used for all workflow-done alerts.
const _workflowDoneChannelId = 'workflow_done';
const _workflowDoneChannelName = 'Workflow Done';
const _workflowDoneChannelDescription =
    'Alerts when an SDLC workflow for a repo has finished.';

/// Thin wrapper around [FlutterLocalNotificationsPlugin].
///
/// A real [FlutterLocalNotificationsPlugin] instance is used by default; a
/// fake/mock can be injected for tests via the [plugin] constructor
/// parameter.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Initializes the underlying plugin. Must be called once at app startup
  /// (see `main.dart`) before [notifyNeedsInput] is used.
  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const darwinSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );
    await _plugin.initialize(settings);
  }

  /// Fires a local notification telling the operator that [sessionName] is
  /// waiting for input.
  ///
  /// Uses `sessionName.hashCode` as the notification id so a repeat
  /// needs-input alert for the same session replaces the previous one
  /// instead of stacking duplicates.
  Future<void> notifyNeedsInput(String sessionName) async {
    const androidDetails = AndroidNotificationDetails(
      _needsInputChannelId,
      _needsInputChannelName,
      channelDescription: _needsInputChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );
    const darwinDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _plugin.show(
      sessionName.hashCode,
      'Needs input',
      '$sessionName is waiting for your input',
      details,
    );
  }

  /// Fires a local notification telling the operator that the [specSlug]
  /// workflow for [repo] has finished with [status] (e.g. `done`/`blocked`).
  ///
  /// Uses `'$repo:$specSlug'.hashCode` as the notification id so a repeat
  /// workflow-done alert for the same repo+spec replaces the previous one
  /// instead of stacking duplicates.
  Future<void> notifyWorkflowDone(
    String repo,
    String specSlug,
    String status,
  ) async {
    const androidDetails = AndroidNotificationDetails(
      _workflowDoneChannelId,
      _workflowDoneChannelName,
      channelDescription: _workflowDoneChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );
    const darwinDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _plugin.show(
      '$repo:$specSlug'.hashCode,
      'Workflow $status',
      '$repo — $specSlug is $status',
      details,
    );
  }
}

// ---------------------------------------------------------------------------
// Riverpod wiring
// ---------------------------------------------------------------------------

/// Injection point for the app's single [NotificationService] instance.
///
/// Defaults to an un-initialized real [NotificationService] — `main.dart`
/// overrides this with an already-[NotificationService.initialize]d instance
/// at app startup. Unlike `bastionSocketProvider`/`bastionApiProvider`, this
/// does not throw when unoverridden: notifications are a best-effort side
/// channel, not a required dependency for the rest of the app to function.
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);

/// Activates the `needs_input` → local-notification bridge.
///
/// Watching this provider subscribes to
/// [needsInputEventsProvider] and calls
/// [NotificationService.notifyNeedsInput] for every event it emits, for as
/// long as the provider stays alive. Must be `watch`n from somewhere in the
/// live widget tree (e.g. the app root) to take effect.
final notificationWiringProvider = Provider.autoDispose<void>((ref) {
  final service = ref.watch(notificationServiceProvider);
  final events = ref.watch(needsInputEventsProvider);

  final StreamSubscription<EventFrame> sub = events.listen((frame) {
    unawaited(service.notifyNeedsInput(frame.session));
  });
  ref.onDispose(sub.cancel);
});

/// Activates the `workflow_done` → local-notification bridge.
///
/// Watching this provider subscribes to
/// [workflowDoneEventsProvider] and calls
/// [NotificationService.notifyWorkflowDone] for every event it emits, for as
/// long as the provider stays alive. Must be `watch`n from somewhere in the
/// live widget tree (e.g. the app root) to take effect — mirrors
/// [notificationWiringProvider].
///
/// Repo-scoped events carry `session: ""`; the repo name, spec slug, and
/// status live in `extra['repo']`/`extra['spec_slug']`/`extra['status']`
/// (serve-api v0.3 §8.2). Events missing any of those fields are ignored
/// rather than crashing the bridge.
final workflowDoneNotificationWiringProvider = Provider.autoDispose<void>((
  ref,
) {
  final service = ref.watch(notificationServiceProvider);
  final events = ref.watch(workflowDoneEventsProvider);

  final StreamSubscription<EventFrame> sub = events.listen((frame) {
    final repo = frame.extra['repo'] as String?;
    final specSlug = frame.extra['spec_slug'] as String?;
    final status = frame.extra['status'] as String?;
    if (repo == null || specSlug == null || status == null) return;
    unawaited(service.notifyWorkflowDone(repo, specSlug, status));
  });
  ref.onDispose(sub.cancel);
});
