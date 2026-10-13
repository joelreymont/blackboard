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
a transcript, and the files remain readable with ordinary tools.

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

The accepted macOS arm64 binary measures **115,836 bytes**. It supports all
seven commands: `init`, `post`, `log`, `unread`, `ack`, `watch`, and `channels`.
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
```

The accepted native runs passed **135/135** cases against the ordinary stripped
Zig ReleaseSmall reference and a smaller signed Zig variant. The ordinary
reference measured 223,760 bytes; the smaller variant measured 170,752 bytes.
See [validation evidence](benchmark/results/README.md) for the limits and review.
The original Zig implementation remains on the
[`zig` branch](https://github.com/joelreymont/blackboard/tree/zig).

Agent collaboration protocol: [SKILL.md](SKILL.md). Development invariants:
[AGENTS.md](AGENTS.md).
