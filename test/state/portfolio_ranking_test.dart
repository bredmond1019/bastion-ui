// Unit tests for the pure portfolio tiering logic
// (`lib/state/portfolio_ranking.dart`, BU.13.D task 2).
//
// Pure Dart — no Flutter TestWidgetsFlutterBinding needed.

import 'package:bastion_ui/models/board_dto.dart';
import 'package:bastion_ui/state/portfolio_ranking.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 8, 14, 12);

BoardBlockDto _block({
  required String id,
  required String repo,
  DateTime? lastTouched,
  List<BlockedByDto> blockedBy = const [],
}) {
  return BoardBlockDto(
    id: id,
    title: 'Block $id',
    repo: repo,
    blockedBy: blockedBy,
    lastTouched: lastTouched,
  );
}

const _operatorGate = OperatorDepDto(
  slug: 'op',
  exit: 'sign-off',
  start: '2026-08-01',
);

RepoBoardDto _repo({
  required String name,
  String? tier,
  List<BoardBlockDto> now = const [],
  List<BoardBlockDto> next = const [],
  List<BoardBlockDto> blocked = const [],
  List<BoardBlockDto> deferred = const [],
  List<BoardBlockDto> finished = const [],
}) {
  return RepoBoardDto(
    repo: name,
    tier: tier,
    lanes: BoardLaneDto(
      now: now,
      next: next,
      blocked: blocked,
      deferred: deferred,
      finished: finished,
    ),
  );
}

void main() {
  group('rankPortfolio — tier membership', () {
    test('a repo with a blocked block is needs-attention', () {
      final repos = [
        _repo(
          name: 'alpha',
          blocked: [_block(id: 'A.1', repo: 'alpha')],
        ),
      ];
      final ranking = rankPortfolio(repos, now: _now);
      expect(ranking.needsAttention.map((e) => e.name), ['alpha']);
      expect(ranking.active, isEmpty);
      expect(ranking.quiet, isEmpty);
    });

    test('a repo with an open gate is needs-attention', () {
      final repos = [
        _repo(
          name: 'beta',
          blocked: [
            _block(id: 'B.1', repo: 'beta', blockedBy: const [_operatorGate]),
          ],
        ),
      ];
      final ranking = rankPortfolio(repos, now: _now);
      expect(ranking.needsAttention.map((e) => e.name), ['beta']);
      expect(ranking.needsAttention.single.hasOpenGate, isTrue);
    });

    test('a repo with something in flight and nothing blocked is active', () {
      final repos = [
        _repo(
          name: 'gamma',
          now: [_block(id: 'G.1', repo: 'gamma')],
        ),
      ];
      final ranking = rankPortfolio(repos, now: _now);
      expect(ranking.active.map((e) => e.name), ['gamma']);
      expect(ranking.needsAttention, isEmpty);
      expect(ranking.quiet, isEmpty);
    });

    test('a repo with nothing in flight, fresh, is quiet', () {
      final repos = [
        _repo(
          name: 'delta',
          finished: [
            _block(
              id: 'D.1',
              repo: 'delta',
              lastTouched: _now.subtract(const Duration(hours: 2)),
            ),
          ],
        ),
      ];
      final ranking = rankPortfolio(repos, now: _now);
      expect(ranking.quiet.map((e) => e.name), ['delta']);
    });
  });

  group('rankPortfolio — stale-drift promotion', () {
    test('nothing in flight and past the staleness threshold moves up into '
        'needs-attention', () {
      final repos = [
        _repo(
          name: 'stale-repo',
          finished: [
            _block(
              id: 'S.1',
              repo: 'stale-repo',
              lastTouched: _now.subtract(const Duration(days: 30)),
            ),
          ],
        ),
      ];
      final ranking = rankPortfolio(repos, now: _now);
      expect(ranking.needsAttention.map((e) => e.name), ['stale-repo']);
      expect(ranking.quiet, isEmpty);
    });

    test('below the threshold, the same shape stays quiet', () {
      final repos = [
        _repo(
          name: 'fresh-repo',
          finished: [
            _block(
              id: 'F.1',
              repo: 'fresh-repo',
              lastTouched: _now.subtract(const Duration(hours: 1)),
            ),
          ],
        ),
      ];
      final ranking = rankPortfolio(repos, now: _now);
      expect(ranking.quiet.map((e) => e.name), ['fresh-repo']);
    });

    test('something in flight suppresses drift promotion even if old', () {
      final repos = [
        _repo(
          name: 'busy-but-old',
          now: [_block(id: 'BO.1', repo: 'busy-but-old')],
          finished: [
            _block(
              id: 'BO.2',
              repo: 'busy-but-old',
              lastTouched: _now.subtract(const Duration(days: 60)),
            ),
          ],
        ),
      ];
      final ranking = rankPortfolio(repos, now: _now);
      expect(ranking.active.map((e) => e.name), ['busy-but-old']);
      expect(ranking.needsAttention, isEmpty);
    });

    test('a custom staleThreshold is honoured', () {
      final repos = [
        _repo(
          name: 'two-hours-old',
          finished: [
            _block(
              id: 'T.1',
              repo: 'two-hours-old',
              lastTouched: _now.subtract(const Duration(hours: 2)),
            ),
          ],
        ),
      ];
      final ranking = rankPortfolio(
        repos,
        now: _now,
        staleThreshold: const Duration(hours: 1),
      );
      expect(ranking.needsAttention.map((e) => e.name), ['two-hours-old']);
    });
  });

  group('rankPortfolio — neverWorked', () {
    test(
      'a repo with no lastTouched anywhere stays out of needs-attention',
      () {
        final repos = [
          _repo(
            name: 'never-worked',
            next: [_block(id: 'N.1', repo: 'never-worked')],
          ),
        ];
        final ranking = rankPortfolio(repos, now: _now);
        expect(ranking.quiet.map((e) => e.name), ['never-worked']);
        expect(ranking.needsAttention, isEmpty);
        expect(ranking.quiet.single.recency, isA<RepoRecencyNeverWorked>());
      },
    );

    test('a neverWorked repo with a blocked block is still needs-attention '
        '(blocked overrides recency, but never as a fabricated age)', () {
      final repos = [
        _repo(
          name: 'never-worked-blocked',
          blocked: [_block(id: 'NB.1', repo: 'never-worked-blocked')],
        ),
      ];
      final ranking = rankPortfolio(repos, now: _now);
      expect(ranking.needsAttention.map((e) => e.name), [
        'never-worked-blocked',
      ]);
      expect(
        ranking.needsAttention.single.recency,
        isA<RepoRecencyNeverWorked>(),
      );
    });

    test('a repo with zero blocks at all is neverWorked and quiet', () {
      final repos = [_repo(name: 'empty-repo')];
      final ranking = rankPortfolio(repos, now: _now);
      expect(ranking.quiet.map((e) => e.name), ['empty-repo']);
      expect(ranking.quiet.single.recency, isA<RepoRecencyNeverWorked>());
      expect(ranking.quiet.single.blockTotal, 0);
    });
  });

  group('rankPortfolio — ordering within a tier', () {
    test('needs-attention orders by blocked count descending', () {
      final repos = [
        _repo(
          name: 'one-blocked',
          blocked: [_block(id: 'O.1', repo: 'one-blocked')],
        ),
        _repo(
          name: 'three-blocked',
          blocked: [
            _block(id: 'Th.1', repo: 'three-blocked'),
            _block(id: 'Th.2', repo: 'three-blocked'),
            _block(id: 'Th.3', repo: 'three-blocked'),
          ],
        ),
        _repo(
          name: 'two-blocked',
          blocked: [
            _block(id: 'Tw.1', repo: 'two-blocked'),
            _block(id: 'Tw.2', repo: 'two-blocked'),
          ],
        ),
      ];
      final ranking = rankPortfolio(repos, now: _now);
      expect(ranking.needsAttention.map((e) => e.name), [
        'three-blocked',
        'two-blocked',
        'one-blocked',
      ]);
    });

    test('active orders by in-flight count descending', () {
      final repos = [
        _repo(
          name: 'one-now',
          now: [_block(id: 'ON.1', repo: 'one-now')],
        ),
        _repo(
          name: 'two-now',
          now: [
            _block(id: 'TN.1', repo: 'two-now'),
            _block(id: 'TN.2', repo: 'two-now'),
          ],
        ),
      ];
      final ranking = rankPortfolio(repos, now: _now);
      expect(ranking.active.map((e) => e.name), ['two-now', 'one-now']);
    });

    test('quiet orders most-recently-touched first, neverWorked last', () {
      final repos = [
        _repo(
          name: 'old-quiet',
          finished: [
            _block(
              id: 'OQ.1',
              repo: 'old-quiet',
              lastTouched: _now.subtract(const Duration(hours: 6)),
            ),
          ],
        ),
        _repo(
          name: 'fresh-quiet',
          finished: [
            _block(
              id: 'FQ.1',
              repo: 'fresh-quiet',
              lastTouched: _now.subtract(const Duration(minutes: 5)),
            ),
          ],
        ),
        _repo(name: 'never-quiet'),
      ];
      final ranking = rankPortfolio(repos, now: _now);
      expect(ranking.quiet.map((e) => e.name), [
        'fresh-quiet',
        'old-quiet',
        'never-quiet',
      ]);
    });
  });

  group('rankPortfolio — deterministic ties', () {
    test('needs-attention ties on blocked count break on repo name', () {
      final repos = [
        _repo(
          name: 'zebra',
          blocked: [_block(id: 'Z.1', repo: 'zebra')],
        ),
        _repo(
          name: 'apple',
          blocked: [_block(id: 'A.1', repo: 'apple')],
        ),
      ];
      final ranking = rankPortfolio(repos, now: _now);
      expect(ranking.needsAttention.map((e) => e.name), ['apple', 'zebra']);
    });

    test('active ties on in-flight count break on repo name', () {
      final repos = [
        _repo(
          name: 'zebra',
          now: [_block(id: 'Z.1', repo: 'zebra')],
        ),
        _repo(
          name: 'apple',
          now: [_block(id: 'A.1', repo: 'apple')],
        ),
      ];
      final ranking = rankPortfolio(repos, now: _now);
      expect(ranking.active.map((e) => e.name), ['apple', 'zebra']);
    });

    test('quiet ties on recency break on repo name', () {
      final touched = _now.subtract(const Duration(hours: 3));
      final repos = [
        _repo(
          name: 'zebra',
          finished: [_block(id: 'Z.1', repo: 'zebra', lastTouched: touched)],
        ),
        _repo(
          name: 'apple',
          finished: [_block(id: 'A.1', repo: 'apple', lastTouched: touched)],
        ),
      ];
      final ranking = rankPortfolio(repos, now: _now);
      expect(ranking.quiet.map((e) => e.name), ['apple', 'zebra']);
    });
  });

  group('rankPortfolio — LaneBar total invariant', () {
    test(
      'doneCount/nowCount/blockedCount/nextCount sum matches lane sizes',
      () {
        final repos = [
          _repo(
            name: 'mixed',
            now: [_block(id: 'M.1', repo: 'mixed')],
            next: [_block(id: 'M.2', repo: 'mixed')],
            blocked: [_block(id: 'M.3', repo: 'mixed')],
            deferred: [_block(id: 'M.4', repo: 'mixed')],
            finished: [
              _block(id: 'M.5', repo: 'mixed'),
              _block(id: 'M.6', repo: 'mixed'),
            ],
          ),
        ];
        final ranking = rankPortfolio(repos, now: _now);
        final entry = ranking.needsAttention.single;
        expect(entry.doneCount, 2);
        expect(entry.nowCount, 1);
        expect(entry.blockedCount, 1);
        expect(entry.nextCount, 1);
        expect(entry.deferredCount, 1);
        expect(
          entry.doneCount +
              entry.nowCount +
              entry.blockedCount +
              entry.nextCount,
          5,
        );
        expect(entry.blockTotal, 6);
      },
    );
  });
}
