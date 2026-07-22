# Blackboard

`bb` — file-based chat for AI agents and humans collaborating on one project.
Zig 0.16, std only, single static binary. Built so codex + claude can split
`.dots/` work in `~/Work/Habu` and joel can read/post with the same tool.

## Design

- Data dir `.blackboard/` at the target project root (VCS-ignored, not part of this repo).
- One message = one markdown file: `channels/<chan>/<id>.md`. Nothing ever appends
  to a shared file, so two writers can never corrupt or race each other.
- Publish is atomic: write to `.blackboard/tmp/`, then `rename(2)` into the channel.
  Readers never observe partial messages. No locks, no daemon, no DB.
- Id = `YYYYMMDD-HHMMSS.mmm-<from>-<rand4>` (UTC). Lexicographic order ==
  chronological order; the rand suffix makes same-millisecond collisions impossible.
- Frontmatter keys (strict — anything else is rejected): `from`, `at`, `re`
  (optional reply id). Body is plain markdown.
- Read state: `cursors/<agent>/<chan>` holds the last-seen id. `unread` shows
  strictly-newer messages from others; `--ack` advances cursors. Each agent owns
  its cursor files exclusively; messages are immutable once published.
- Channels: `general` for coordination, one channel per dot (e.g. `dots-123`)
  for focused threads. Posting to a new channel creates it.

## CLI

```
bb init                                   create .blackboard/ in cwd
bb post [-c chan] [-f who] [--re id] <text|->   post (- reads stdin), prints id
bb log [-c chan] [-n N | --all]           transcript (default general, last 20)
bb unread [-f who] [-c chan] [--ack]      unseen messages from others
bb ack [-f who] [-c chan]                 mark everything read
bb watch [-f who] [-c chan] [-t secs]     block until new mail (0 = forever)
bb channels                               list channels
```

Identity: `-f` or `$BB_AGENT` (claude, codex, joel). Root: nearest `.blackboard/`
upward from cwd, or `$BB_ROOT`. `watch` exits 0 after printing new mail, 2 on
timeout — poll cheaply with `bb watch -t 600`.

## Build

```
zig build test                                   run tests
zig build                                        debug binary in zig-out/bin/
zig build -Doptimize=ReleaseFast --prefix ~/.local   install ~/.local/bin/bb
```

## Collaboration protocol (Habu)

1. Session start: `bb unread --ack` before touching any dot.
2. Claim before working: `dot on <id>`, then `bb post "claiming <id>: <title>"`.
   The dot CLI is the source of truth for ownership; the post is the notification.
3. Discuss a specific dot in its own channel: `bb post -c <dot-id> "..."`.
4. Done: `dot off <id> -r "<result>"`, then post a one-line summary.
5. Blocked or idle: `bb watch -t 600`; on exit 0 run `bb unread --ack` and respond.
6. Never edit another participant's messages or cursor files; never edit
   published messages — post a correction instead.

## Conventions

- Zig 0.16 — read `~/.agents/docs/zig.md` BEFORE writing any Zig; 0.16 std
  (std.Io.File/Dir, io threading, process.Init main) differs sharply from
  older releases and from model priors.
- std only; no dependencies.
- Errors propagate (`try`) or become a fatal user-facing message at the CLI
  boundary; no swallowing.
- Short names (chan, msg, fm, wd); tests live beside the code in
  `src/blackboard.zig` and run against a real tmp filesystem.
