/// The serve-api contract version this client's model layer mirrors.
///
/// Owned upstream by `bastion` in `../bastion/docs/serve-api.md` (Standing
/// Rule 6 — the contract is upstream and pinned, never invented here).
/// `bastion-ui` is a thin client: this constant records the exact contract
/// revision the Dart model layer (`lib/models/*_dto.dart`) and the matching
/// `BastionApi` methods were written against.
///
/// This is the app's first explicit, machine-checkable version pin — see
/// `test/services/serve_api_version_test.dart`, which asserts this value
/// against the upstream doc's title/H1 line whenever a sibling `bastion`
/// checkout is present, and skips cleanly (never fails) when it is not
/// (D64 un-gateable-AC rule: evidence living in another repo's working tree
/// must be declared, not gated).
///
/// Before this pin existed, the contract version was tracked only in prose
/// comments, which is how the client drifted 25 contract versions without
/// anything failing.
const String kServeApiPin = 'v0.31';
