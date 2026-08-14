import 'package:flutter_test/flutter_test.dart';

import 'package:bastion_ui/models/docs_dto.dart';

void main() {
  group('DocEntryDto', () {
    test('decodes a file entry', () {
      final entry = DocEntryDto.fromJson({
        'path': 'planning/status.md',
        'name': 'status.md',
        'is_dir': false,
      });

      expect(entry.path, 'planning/status.md');
      expect(entry.name, 'status.md');
      expect(entry.isDir, isFalse);
    });

    test('decodes a directory entry', () {
      final entry = DocEntryDto.fromJson({
        'path': 'planning/decisions',
        'name': 'decisions',
        'is_dir': true,
      });

      expect(entry.isDir, isTrue);
    });
  });

  group('DocTreeDto', () {
    test('a tree with nested directories and files', () {
      final tree = DocTreeDto.fromJson({
        'repo': 'bastion',
        'root': 'planning',
        'entries': [
          {'path': 'planning/status.md', 'name': 'status.md', 'is_dir': false},
          {'path': 'planning/decisions', 'name': 'decisions', 'is_dir': true},
          {
            'path': 'planning/decisions/D1.md',
            'name': 'D1.md',
            'is_dir': false,
          },
        ],
      });

      expect(tree.repo, 'bastion');
      expect(tree.root, 'planning');
      expect(tree.entries, hasLength(3));
      expect(tree.entries[0].isDir, isFalse);
      expect(tree.entries[1].isDir, isTrue);
      expect(tree.entries[2].path, 'planning/decisions/D1.md');
    });

    test('an empty tree (entries absent) defaults to an empty list', () {
      final tree = DocTreeDto.fromJson({'repo': 'bastion', 'root': ''});

      expect(tree.repo, 'bastion');
      expect(tree.root, '');
      expect(tree.entries, isEmpty);
    });
  });

  group('DocFileDto', () {
    test('a file payload with modified present', () {
      final file = DocFileDto.fromJson({
        'repo': 'bastion',
        'path': 'planning/status.md',
        'content': '---\ntype: Status\n---\n\n# bastion — Status\n',
        'bytes': 8421,
        'modified': '2026-07-24T18:03:11Z',
      });

      expect(file.repo, 'bastion');
      expect(file.path, 'planning/status.md');
      expect(file.content, contains('type: Status'));
      expect(file.bytes, 8421);
      expect(file.modified, '2026-07-24T18:03:11Z');
    });

    test('a file payload with modified absent', () {
      final file = DocFileDto.fromJson({
        'repo': 'bastion',
        'path': 'planning/status.md',
        'content': 'content',
        'bytes': 7,
      });

      expect(file.modified, isNull);
    });

    test('a file with empty content', () {
      final file = DocFileDto.fromJson({
        'repo': 'bastion',
        'path': 'planning/empty.md',
        'content': '',
        'bytes': 0,
      });

      expect(file.content, isEmpty);
      expect(file.bytes, 0);
    });
  });
}
