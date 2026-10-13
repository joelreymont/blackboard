# Blackboard

`bb` is a single Habu source file (`main.f`) compiled for macOS arm64. This
file covers work on the CLI; the agent usage protocol is in [SKILL.md](SKILL.md)
and `~/.agents/docs/bb.md`.

## Invariants

- A message is one immutable Markdown file at
  `.blackboard/channels/<channel>/<id>.md`; no shared file is appended.
- Post publishes atomically: write a complete file to `.blackboard/tmp/`, then
  rename it into the channel. Readers must not observe partial messages.
- IDs encode UTC milliseconds plus a random suffix. Lexical order is display
  order, not proof of publication order; delayed files may have older IDs.
- Frontmatter accepts `from`, `at`, and optional `re`. Unknown keys are fatal
  `BadMessage` errors that name the offending file.
- Each agent owns only its `cursors/<agent>/<channel>` files. Cursors contain
  exact acknowledged IDs; `unread` excludes those IDs and own messages.
  Legacy single-ID cursors acknowledge only that ID, so migration can replay
  older messages once. `watch` never writes or upgrades cursors.
- Cursor commits merge the captured scan under an agent-directory lock and
  publish by atomic rename. `unread --ack` delivers output before committing;
  failed scans or failed output must not acknowledge undelivered messages.
- `watch` must remain event-driven. Its macOS FSEvents stream wakes scans of
  the opened board and detects newly created channels. Preserve the held
  board and registered channel inode behavior across moves and replacements.
- CLI output and errors are the contract. Preserve behavior against the
  differential suite, especially atomic post, cursor state and watch timing.

## Workflow

- Read the Habu release documentation before editing `main.f`. Use the pinned
  `c53b4d2c` compiler; `build.sh` checks its SHA-256. Do not modify or vendor
  the compiler into this repository.
- Build: `sh build.sh`; output is `bin/bb` (ignored).
- Full macOS differential test: `sh tests/build-reference.sh`, then
  `python3 tests/differential.py .build/bb-zig-reference bin/bb`. This compares
  the complete CLI with the preserved Zig reference; run it after CLI changes.
  Intentional cursor-format and diagnostic fixes have explicit expectations;
  never change the preserved reference or broadly ignore state/output drift.
- Correctness regressions: `python3 tests/regressions.py bin/bb --watch`.
  Fixtures use synthetic HOME and private BB_ROOT. Native FSEvents checks need
  access to the host event stream; a sandbox start failure is not a timeout.
- Generated binaries, test boards, and caches belong in ignored `.build/` or
  `bin/`. Commit source, tests, and concise evidence only.
- `CLAUDE.md` is a symlink to this file; keep the link intact.
