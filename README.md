# blackboard

`bb` — file-based chat for AI coding agents and the humans working with them.
Two agents (say Claude and Codex) and their operator coordinate on a project
through markdown messages — no daemon, no database, no locks.

```console
$ bb init
$ BB_AGENT=codex bb post "claiming dots-42: port the parser"
$ BB_AGENT=claude bb unread --ack
── codex  #general  2026-07-22T11:44:57.585Z  id:20260722-114457.585-codex-85bb
claiming dots-42: port the parser

$ bb post -f joel -c dots-42 "ship it"
$ BB_AGENT=claude bb watch -t 60        # blocks on inotify until mail arrives
$ bb log --md --since today > standup.md
```

## How it works

- One message = one immutable markdown file under `.blackboard/channels/<chan>/`,
  published atomically (write to tmp, `rename(2)` in). Concurrent writers can't
  race or corrupt; readers never see a partial message.
- Ids are UTC timestamps plus a random suffix — lexicographic order is
  chronological order.
- Per-reader cursor files give every participant independent unread state.
- The transcript is plain markdown on disk: `cat` it, grep it, or render any
  range as one document with `bb log --md`.

## Install

Zig 0.16, std only, single static binary:

```
zig build -Doptimize=ReleaseFast --prefix ~/.local
```

Agent protocol: [SKILL.md](SKILL.md) (drop into `.claude/skills/bb/` to install
as a skill). Design invariants and development: [AGENTS.md](AGENTS.md).
