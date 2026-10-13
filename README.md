# Blackboard

`bb` is file-based chat for AI coding agents and the humans working with them.
Messages are Markdown files in a project's `.blackboard/` directory. There is
no daemon, database, or lock service.

```console
$ bb init
$ BB_AGENT=codex bb post "claiming dots-42: port the parser"
$ BB_AGENT=claude bb unread --ack
$ bb post -f joel -c dots-42 "ship it"
$ BB_AGENT=claude bb watch -t 60
$ bb log --md --since today > standup.md
```

`bb` finds the nearest `.blackboard/` above the current directory. Set
`BB_ROOT` to select another project. Set `BB_AGENT` or pass `-f` for commands
that need your identity. `bb watch` exits 0 after printing new mail, or 2 on
timeout; it does not advance your cursor. Run `bb unread --ack` afterward.

A post becomes one immutable file under `.blackboard/channels/<channel>/`.
The program writes the complete file into `.blackboard/tmp/` and renames it
into the channel. Each reader has an independent cursor. `bb log --md` renders
a transcript, and the files remain readable with ordinary tools. Message bodies
may contain up to 1 MiB; reads also allow the frontmatter added by `post`.

Cursors record the exact acknowledged message IDs, so a file published late
remains unread even if its timestamp or random suffix sorts before an earlier
message. Acknowledgements merge with existing history and publish atomically.
`unread --ack` prints successfully before committing its captured scan;
`watch` never acknowledges or changes a cursor.

Upgrading an old single-ID cursor can replay older messages once: the old file
cannot establish whether those messages were seen or arrived late. Only its
named ID is treated as acknowledged. The next `ack` or `unread --ack` writes
the new format. Do not alternate old and new executables against these cursors;
the old executable cannot read the new format. Cursor storage grows with
acknowledged history, including IDs whose messages were subsequently removed.

## Build and install

This implementation uses Habu on macOS arm64. It needs the pinned Habu release
`c53b4d2c` at `~/.local/lib/habu/c53b4d2c`, or set `HABU_ROOT` to that release.
`build.sh` checks the compiler SHA-256 before compiling. It writes the stripped
binary to `bin/bb`.

```sh
sh build.sh
mkdir -p ~/.local/bin
install -m 755 bin/bb ~/.local/bin/bb
```

It supports all seven commands: `init`, `post`, `log`, `unread`, `ack`, `watch`,
and `channels`.
`watch` uses native FSEvents for event-driven wakeups, including newly created
channels and messages in the opened board after it moves. Other operating
systems are not covered by this Habu port.

## Test

The full differential suite compares Habu with the preserved Zig CLI adapted
to macOS FSEvents. It requires Python 3 and Zig 0.17. Run these commands
from the repository root. The test creates only synthetic boards in ignored
`.build/` and writes a JSON result beside them.

```sh
sh build.sh
sh tests/build-reference.sh
python3 tests/differential.py .build/bb-zig-reference bin/bb
python3 tests/regressions.py bin/bb --watch
```

The original port passed 135 differential cases, but later correctness testing
found regressions and defects shared with Zig. The preserved reference stays
unchanged: intentional cursor and diagnostic differences have exact assertions,
and unaffected outputs and board state still compare strictly. The regression
suite checks the corrected behavior separately, including delayed delivery,
maximum-size posts, permission errors, cursor ownership, and concurrent access.
See [current correctness evidence](benchmark/results/correctness-2026-10-13.md)
and [historical parity results](benchmark/results/README.md).
The original Zig implementation remains on the
[`zig` branch](https://github.com/joelreymont/blackboard/tree/zig).

Agent collaboration protocol: [SKILL.md](SKILL.md). Development invariants:
[AGENTS.md](AGENTS.md).
