# Blackboard

`bb` — file-based chat for AI agents and humans collaborating on one project.
Zig 0.16, std only, single static binary. This file covers working on the bb
codebase; usage and collaboration protocol live in `~/.agents/docs/bb.md`.

## Design invariants

- One message = one immutable markdown file `channels/<chan>/<id>.md`. Nothing
  ever appends to a shared file; two writers can never corrupt or race.
- Publish is atomic: write to `.blackboard/tmp/`, then `rename(2)` into the
  channel. Readers never observe partial messages. No locks, no daemon, no DB.
- Id = `YYYYMMDD-HHMMSS.mmm-<from>-<rand4>` (UTC). Lexicographic order ==
  chronological; rand suffix removes same-millisecond collisions.
- Frontmatter is strict (`from`, `at`, optional `re`); unknown keys are
  `error.BadMessage`, surfaced as a fatal naming the file.
- Each agent exclusively owns its `cursors/<agent>/<chan>` files; `unread`
  shows strictly-newer messages from others.
- `watch` is event-driven (inotify + poll), never sleep-polling; new channel
  dirs are detected via a watch on `channels/` itself.
- The `usage_text` in `src/main.zig` is the CLI contract; smoke tests exercise
  the installed binary, unit tests the lib against a real tmp filesystem.

## Build

```
zig build test                                       run tests
zig build                                            debug binary in zig-out/bin/
zig build -Doptimize=ReleaseFast --prefix ~/.local   install ~/.local/bin/bb
```

## Conventions

- Zig 0.16 — read `~/.agents/docs/zig.md` BEFORE writing any Zig; 0.16 std
  (std.Io.File/Dir, io threading, process.Init main) differs sharply from
  older releases and from model priors.
- std only; no dependencies.
- Errors propagate (`try`) or become a fatal user-facing message at the CLI
  boundary; no swallowing.
- Short names (chan, msg, fm, wd); tests live beside the code in
  `src/blackboard.zig`.
