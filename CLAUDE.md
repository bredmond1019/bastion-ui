# CLAUDE.md — BastionUI

Flutter mobile Surface (Android phone + tablet) for remotely operating the whole Bastion practice OS over Tailscale, backed by a bastion serve HTTP+WebSocket API.

## Before you start

- **Strategic context:** `planning/context.md` (read first) → `planning/status.md` (current state)
- **Symlink warning:** the `planning/` directory is actually a local symlink pointing to the company brain repo's `_planning/` vault (e.g. `core/_planning/bastion-ui/`). The brain repo is responsible for tracking all planning files under Git. Do not track `planning/` in this project's public Git repository (it is gitignored).
- **Symlink traps:** `rg`/`grep`/`find` are symlink-blind by default — a search that must include `planning/` content needs `-L`/`--follow`. `git mv` fails through the symlink face ("source directory is empty") — move planning files via the real vault path (`.../_planning/<slug>/...`), never via `planning/...`. Planning changes are committed in the brain repo (`agentic-portfolio`) with an explicit pathspec, never in this repo.
- **Plan:** `planning/master-plan.md` — the phase/block sequence
- **Pipeline config:** `planning/harness.json` — the validation commands + UI-test config the
  SDLC engines run (see `planning/harness.examples.md` for ready-made stack profiles)
- **Decisions log:** `planning/decisions/` (start at `planning/decisions/index.md`) — check
  before relitigating any settled choice

## Standing rules

1. **Every new function, module, or behaviour change ships with tests.** No exceptions — this applies to ad-hoc fixes and one-off changes just as much as formal blocks/tasks. If you add or change code, add or update the tests that cover it.
2. **OKF frontmatter is required on every new `.md` file** under `docs/` and `planning/`.
   Every new file must open with a YAML frontmatter block. Three fields are **required**:
   `type`, `title`, `description`. Six fields are **optional but strongly encouraged**:
   - `doc_id` — kebab-case stable id (defaults to filename stem if omitted)
   - `layer` — list from closed vocab: `brain` · `engine` · `factory` · `console` · `surface` · `infra` · `business` · `content` · `meta`
   - `project` — controlled slug (this repo: `bastion-ui`; omit for genuinely cross-cutting docs); closed vocab: `bastion` · `python-orchestration` · `learn-ai` · `rag-engine-rs` · `claude-sdk-rs` · `workflow-engine-rs` · `markdown-engine-validator` · `bella` · `price-scout` · `amistad` · `base-template` · `brain`
   - `status` — one of: `active` · `draft` · `deprecated` · `superseded` · `archived`
   - `keywords` — 3–7 free-form topic terms; never exceed 7
   - `related` — list of `doc_id` values from other real docs in the repo
   Canonical guide: `docs/okf-frontmatter.md` in the company-brain repo; governing decision: D27.
   **Adding a file to a directory also requires updating that directory's `index.md`** — propagate
   up the chain if the parent directory's scope changes.
3. **Sequence, not calendar** — work the order in `master-plan.md`; pick up where you left off.
4. **Decisions are append-only** — never edit a settled decision; supersede it with a new
   atomic file in `planning/decisions/` and link back.
5. **Verified identity / handles:** none — treat these as the only authoritative
   identities/URLs; flag any other handle or profile link as unverified before publishing it.
6. **The contract is upstream and pinned, never invented here.** BastionUI is a *thin client*
   over `bastion serve`. The HTTP routes + WebSocket frame schema are owned by `bastion` in
   `bastion/docs/serve-api.md` (versioned, D20-style). This repo **mirrors** that schema in its
   Dart model layer and **pins** a version — it never defines or changes a route/frame. If the app
   needs a new endpoint or field, that is a change request against `bastion`'s serve-api, not a
   local addition.
7. **Tailnet-only, thin, read-mostly.** The app talks only to `bastion serve` over the Tailscale
   tailnet (plain HTTP+WS; Tailscale provides encryption). It never shells tmux, touches git, or
   writes Engine state directly — every action is a call to the gateway. The bearer token is stored
   via `flutter_secure_storage`, never `shared_preferences`.

## Known bugs

None known at initialization.

## Build / test / run

```bash
flutter pub get                                   # install deps
dart format --output=none --set-exit-if-changed lib test # format check (gating)
flutter analyze                                   # static analysis (gating)
flutter test                                      # unit + widget tests (gating)
flutter run                                        # run on a connected device/emulator
flutter build apk                                  # build an Android APK
```

> The SDLC pipeline reads its gating suite from `planning/harness.json` (format → analyze →
> test). The live end-to-end run against a real `bastion serve` over Tailscale is a **manual**
> verification step, not an automated gate (no devserver/route UI-test stage for a mobile app).
> To do that verification: `scripts/start_dev_env.sh` boots an emulator + a local `bastion
> serve` (reusing either if already up) and launches `flutter run` against it, bailing with a
> specific diagnosis on failure rather than a generic error. See `docs/testing.md` ("Manual
> dev environment" section) for what it checks and its failure modes.

## Directory map

```
bastion-ui/
├── .claude/        ← Claude Code commands + SDLC workflow engines
├── planning/       ← context, status, master-plan, harness.json, decisions/, <concept>/
└── lib/            ← Flutter app source
    ├── models/     ← DTOs + frame (de)serialization mirroring serve-api.md (pure, unit-tested)
    ├── services/   ← bastion_socket.dart (WS + reconnect), bastion_api.dart (REST)
    ├── state/      ← riverpod (or provider) providers
    ├── screens/    ← connection/settings, sessions, dashboard, repo detail, quick-actions
    └── widgets/    ← session card, pane view, approve-button row, status badge, markdown view
```

## What NOT to touch

- **The serve-api contract** (`bastion/docs/serve-api.md`) lives in the `bastion` repo — never
  edit it from here; request changes upstream (Standing Rule 6).

---

## SDLC pipeline

This project carries the curated SDLC harness. Run `/prime` to orient, then drive structured
work through `/generate-tasks → /implement → /test → /review-task → /document → /log-work`.
See `.claude/commands/README.md` for the full pipeline reference.

> **Stack note:** the SDLC engines carry no stack defaults. Point them at this project's stack
> by filling `planning/harness.json` (validation commands + optional UI-test config). Copy a
> ready-made profile from `planning/harness.examples.md` (Rust / Python / Next.js). Do **not**
> edit the `workflows/*.js` engines for stack reasons — that's what `harness.json` is for.

<!-- BEGIN:response-style -->
## Response Style

You are read by an operator scanning several concurrent agent sessions. Long prose is the failure
mode, not thoroughness.

1. **First line = the outcome** — what happened, and whether it needs them.
2. **Then the specifics** — bullets, one line each, max ~6. Facts, not narration.
3. **Last line = the ask**, if there is one. One question, answerable in a word.

**Ceiling: 10 lines for a normal turn, 20 for an end-of-run report.** Only depth the operator
explicitly asked for may exceed it.

Durable detail goes to disk — the commands already require that. **Link the path; do not restate
the file.** Lead with failures, blocks, and anything that did not match the ask, in plain words with
the real error text. Cut reasoning narration, unasked-for next steps, and self-assessment.

Full rationale, the complete cut-list, and worked before/after examples: the
**`report-to-the-operator`** skill.
<!-- END:response-style -->
