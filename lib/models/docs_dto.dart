/// Docs DTOs mirroring `../bastion/types/serve.ts` (serve-api v0.30/v0.31
/// §16) for `GET /api/docs/{repo}/tree` and `GET /api/docs/{repo}/file`.
///
/// This file is pure Dart — no Flutter or socket imports.
library;

// ---------------------------------------------------------------------------
// DocEntryDto
// ---------------------------------------------------------------------------

/// One entry (file or directory) in a docs tree listing — mirrors
/// `DocEntryDto` in `types/serve.ts`.
final class DocEntryDto {
  /// Repo-root-relative path — exactly what `GET /api/docs/{repo}/file`'s
  /// `?path=` accepts.
  final String path;

  /// The entry's base name (final path component).
  final String name;

  /// `true` when the entry is a directory (expandable), `false` for a file
  /// (openable). This is the field the tree widget branches on.
  final bool isDir;

  const DocEntryDto({
    required this.path,
    required this.name,
    required this.isDir,
  });

  factory DocEntryDto.fromJson(Map<String, dynamic> json) {
    return DocEntryDto(
      path: json['path'] as String? ?? '',
      name: json['name'] as String? ?? '',
      isDir: json['is_dir'] as bool? ?? false,
    );
  }
}

// ---------------------------------------------------------------------------
// DocFileDto
// ---------------------------------------------------------------------------

/// JSON response for `GET /api/docs/{repo}/file?path=<rel-file>` — mirrors
/// `DocFileDto` in `types/serve.ts`.
final class DocFileDto {
  /// Echoes the resolved workspace registry name.
  final String repo;

  /// The validated, repo-root-relative path that was read.
  final String path;

  /// The file's raw markdown, byte-for-byte — no rendering, no frontmatter
  /// stripping, no sentinel removal. The server owns traversal rejection
  /// (serve-api §16.2); this client does not sanitise, resolve or rewrite
  /// paths itself.
  final String content;

  /// Content length in bytes.
  final int bytes;

  /// Filesystem mtime, RFC 3339 UTC; absent when unavailable.
  final String? modified;

  const DocFileDto({
    required this.repo,
    required this.path,
    required this.content,
    required this.bytes,
    this.modified,
  });

  factory DocFileDto.fromJson(Map<String, dynamic> json) {
    return DocFileDto(
      repo: json['repo'] as String? ?? '',
      path: json['path'] as String? ?? '',
      content: json['content'] as String? ?? '',
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      modified: json['modified'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// DocTreeDto — GET /api/docs/{repo}/tree response
// ---------------------------------------------------------------------------

/// JSON response for `GET /api/docs/{repo}/tree?path=<rel-dir>` — mirrors
/// `DocTreeDto` in `types/serve.ts`.
final class DocTreeDto {
  /// Echoes the resolved workspace registry name.
  final String repo;

  /// The allowlisted root (or subtree) the listing is relative to; `""`
  /// when the whole allowlist was walked.
  final String root;

  /// Sorted directories-first, then by `name`. Only markdown-bearing
  /// entries appear. OPTIONAL on the wire (`entries?` in the TS); an
  /// absent key defaults to an empty list.
  final List<DocEntryDto> entries;

  const DocTreeDto({
    required this.repo,
    required this.root,
    this.entries = const [],
  });

  factory DocTreeDto.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'];
    return DocTreeDto(
      repo: json['repo'] as String? ?? '',
      root: json['root'] as String? ?? '',
      entries: rawEntries is List
          ? rawEntries
                .whereType<Map<String, dynamic>>()
                .map(DocEntryDto.fromJson)
                .toList()
          : const [],
    );
  }
}
