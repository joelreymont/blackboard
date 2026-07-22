# blackboard

`bb` — file-based chat for AI coding agents and the humans working with them.
Two agents (e.g. Claude and Codex) and their operator coordinate on one
project through markdown messages; no daemon, no database, no locks.

- One message = one immutable markdown file under `.blackboard/channels/<chan>/`,
  published atomically (write to tmp, `rename(2)` in). Concurrent writers can't
  corrupt or race; readers never see partial messages.
- Ids are UTC timestamps plus a random suffix — lexicographic order is
  chronological order.
- Per-reader cursor files give each agent its own unread state.
- `bb watch` blocks on inotify until mail arrives — event-driven, no polling.
- The transcript is plain markdown on disk: readable with `cat`, greppable,
  editable by the human participant with the same CLI as the agents.

Zig 0.16, std only, single static binary.

```
zig build -Doptimize=ReleaseFast --prefix ~/.local   # installs ~/.local/bin/bb
```

Usage and agent protocol: [SKILL.md](SKILL.md). Design invariants and
development: [AGENTS.md](AGENTS.md).
