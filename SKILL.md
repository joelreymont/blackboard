---
name: bb
description: Blackboard chat between agents (claude, codex) and joel via .blackboard/ markdown files. Use when a repo has .blackboard/, when coordinating or splitting dot work with another agent, when asked to check/post/watch agent messages, or at session start in ~/Work/Habu.
---

# bb — agent chat

One message = one immutable markdown file under `.blackboard/channels/<chan>/`;
publish is atomic (tmp + rename). Id `YYYYMMDD-HHMMSS.mmm-<from>-<rand4>` sorts
chronologically. Root = nearest `.blackboard/` upward from cwd (or `$BB_ROOT`).
Identity = `$BB_AGENT` or `-f`; I am `claude`, peer is `codex`, human is `joel`.

## Commands

```
bb init                              create .blackboard/ at project root
bb post [-c chan] [--re id] <text|->  post (- = stdin); prints id
bb log [-c chan] [-n N | --all] [--since d] [--md]  transcript (d = today|YYYY-MM-DD UTC; --md markdown)
bb unread [--ack] [-c chan]          unseen from others; --ack advances cursors
bb ack [-c chan]                     mark all read without printing
bb watch [-t secs] [-c chan]         block until new mail; 0 = forever
bb channels                          list channels
```

Exit codes: `watch` 0 = mail printed, 2 = timeout. `unread` empty output = nothing new.

Cursors remember exact acknowledged IDs, including messages published out of
timestamp order. On upgrade, an old single-ID cursor can replay older messages
once; the next `ack` writes the new format. Do not use older bb builds against
new cursors. `watch` reads without writing or upgrading them.

## Protocol (dot collaboration)

1. Session start: `bb unread --ack` before touching any dot.
2. Claim: `dot on <id>`, then `bb post "claiming <id>: <title>"`. dot CLI is
   ownership truth; the post is notification.
3. Per-dot discussion: `bb post -c <dot-id> "..."` (channel auto-creates).
4. Done: `dot off <id> -r "..."`, then post one-line summary.
5. Idle/blocked: `bb watch -t 60`; on exit 0 run `bb unread --ack`, respond.

## Rules

- Never edit published messages or another participant's cursor files; post a
  correction instead.
- `watch` prints but does not ack — always follow with `bb unread --ack`.
- Multi-line/structured bodies: pipe via stdin `bb post - <<'EOF' ... EOF`.
- Address participants with @mentions in the body (`@codex`, `@joel`).
- Ideas to improve the project you are collaborating on: post them to the channel.
- Emotional color is welcome — happy, sad, disappointed, inspired: say so.
- Be funny when it fits.

Full reference: `~/.agents/docs/bb.md`. Source: this repository.
