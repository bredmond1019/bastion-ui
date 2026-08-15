// ignore_for_file: avoid_relative_lib_imports
//
// `repo_board_provider.dart` (`BU.13.C` task 1) tests, built on the shared
// integration-tier fixtures (`test/support/fake_http_transport.dart`,
// `test/support/wire_fixtures.dart` — `BU.ticket.integration-test-tier`),
// not a new bespoke fake — mirrors `briefing_provider_test.dart`'s setup.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/board_dto.dart';
import 'package:bastion_ui/services/bastion_api.dart';
import 'package:bastion_ui/state/briefing_model.dart';
import 'package:bastion_ui/state/repo_board_provider.dart';
import 'package:bastion_ui/state/sessions_provider.dart'
    show bastionApiProvider;

import '../support/fake_http_transport.dart';
import '../support/wire_fixtures.dart';

Future<void> pump([int rounds = 5]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

void main() {
  late FakeHttpTransport httpTransport;
  late BastionApi api;
  late ProviderContainer container;

  setUp(() {
    httpTransport = FakeHttpTransport();
    api = BastionApi(
      host: 'test-host',
      port: 4317,
      token: 'test-token',
      transport: httpTransport,
    );
    container = ProviderContainer();
    container.read(bastionApiProvider.notifier).state = api;
    addTearDown(container.dispose);
  });

  test('sends scope=project, repo=<name>, graph=true', () async {
    httpTransport.on(
      'GET',
      '/api/board',
      status: 200,
      body: boardProjectFixture,
    );

    container.read(repoBoardProvider('bastion-ui'));
    await pump();

    final call = httpTransport.lastCallTo('GET', '/api/board');
    expect(call, isNotNull);
    expect(call!.queryParameters['scope'], 'project');
    expect(call.queryParameters['repo'], 'bastion-ui');
    expect(call.queryParameters['graph'], 'true');
  });

  test('selects the matching RepoBoardDto out of several repos', () async {
    final multiRepoBoard = {
      'scope': 'project',
      'lanes': boardLaneFullFixture,
      'repos': [
        {
          'repo': 'other-repo',
          'tier': 'core',
          'lanes': {
            'now': [boardBlockMinimalFixture],
          },
        },
        {
          'repo': 'bastion-ui',
          'tier': 'core',
          'lanes': {
            'now': [boardBlockFullFixture],
          },
        },
      ],
      'stale': false,
    };
    httpTransport.on('GET', '/api/board', status: 200, body: multiRepoBoard);

    final state = container.read(repoBoardProvider('bastion-ui'));
    expect(state, isA<BriefingSectionLoading<BoardLaneDto>>());
    await pump();

    final loaded =
        container.read(repoBoardProvider('bastion-ui'))
            as BriefingSectionLoaded<BoardLaneDto>;
    expect(loaded.data.now, hasLength(1));
    expect(loaded.data.now.single.id, boardBlockFullFixture['id']);
  });

  test(
    'a repo absent from repos[] yields an empty lane state, not an error',
    () async {
      httpTransport.on(
        'GET',
        '/api/board',
        status: 200,
        body: boardProjectFixture, // repos[] only contains "bastion-ui"
      );

      container.read(repoBoardProvider('some-other-repo'));
      await pump();

      final state =
          container.read(repoBoardProvider('some-other-repo'))
              as BriefingSectionLoaded<BoardLaneDto>;
      expect(state.data.now, isEmpty);
      expect(state.data.next, isEmpty);
      expect(state.data.blocked, isEmpty);
      expect(state.data.deferred, isEmpty);
      expect(state.data.finished, isEmpty);
    },
  );

  test('a 500 response yields an error state', () async {
    httpTransport.on(
      'GET',
      '/api/board',
      status: 500,
      body: {'error': 'internal', 'code': 'C000', 'message': 'boom'},
    );

    container.read(repoBoardProvider('bastion-ui'));
    await pump();

    final state = container.read(repoBoardProvider('bastion-ui'));
    expect(state, isA<BriefingSectionError<BoardLaneDto>>());
    expect((state as BriefingSectionError<BoardLaneDto>).message, isNotEmpty);
  });

  test('two different repo names are independent family members', () async {
    httpTransport.on(
      'GET',
      '/api/board',
      status: 200,
      body: boardProjectFixture,
    );

    container.read(repoBoardProvider('bastion-ui'));
    container.read(repoBoardProvider('mev'));
    await pump();

    final a = container.read(repoBoardProvider('bastion-ui'));
    final b = container.read(repoBoardProvider('mev'));
    expect(a, isA<BriefingSectionLoaded<BoardLaneDto>>());
    expect(b, isA<BriefingSectionLoaded<BoardLaneDto>>());
    // Distinct calls were made per repo.
    expect(httpTransport.callCount('GET', '/api/board'), 2);
  });
}
