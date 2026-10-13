# Historical macOS differential result

> Historical result: the later correctness audit found issues this comparison
> missed. See [the repairs and current verification](correctness-2026-10-13.md).

The Habu port was checked against the complete Blackboard CLI at upstream
commit `614c8774ab70cd48782c7fe8e38a527aa78c3d5b`. The Zig reference
preserves `blackboard.zig` byte for byte; `main.zig` adapts Linux inotify/poll
to macOS FSEvents so its watch command can run on this host. The adaptation
diff is [`../../tests/reference/macos-watch.diff`](../../tests/reference/macos-watch.diff).

On 2026-10-13, native runs passed **135/135** cases against both the ordinary
stripped Zig ReleaseSmall reference and a separately stripped and signed
minimal Zig variant. The saved per-case results are
[`full-parity-small.json`](full-parity-small.json) and
[`full-parity-smallest.json`](full-parity-smallest.json). The suite compares
exit status, stdout, stderr, cursor files and board state where deterministic.
Generated IDs and timestamps are checked by format and content; watch cases
check bounded timing and observed event behavior. Coverage includes all seven
commands, invalid inputs, malformed messages, concurrency, root moves,
channel inode moves, replacement channels and 70 channels with a 64-FD limit.

| Complete macOS arm64 CLI | Stripped bytes |
| --- | ---: |
| Habu (`main.f`) | 115,836 |
| Zig ReleaseSmall reference | 223,760 |
| Zig minimal signed variant | 170,752 |

The Habu compiler was pinned to release `c53b4d2c`, SHA-256
`ccf0798dd4e11a3ea4308386704bd09a5f183750d18b802b9b2d9c28d6af2b96`.
Source SHA-256: `main.f`
`a9296968b1cf138d5766340e33d478427f46822f8dc5949e6eb4d0ae72c4f540`,
reference `main.zig`
`5988730e7552e26092e7f6a9b89ae6143829d76aed19da55df1f45d10f9c837b`,
reference `blackboard.zig`
`dffac7a1fef988d922cb1a3d0a3359ae10a5f3d29140fb32ae0f2611ad54840b`.
The [focused independent review](final-review.md) accepted the four repaired
behaviors with no remaining finding in that scope. The roughly 24.85-day
timeout clamp was checked in source, since a real-time runtime test would
require multiple weeks. Native filesystem APIs can differ in event race
timing; the suite does not claim every possible schedule matches.

The [minimal Zig measurement](zig-smallest-measurement.json) records the
compiler flags, symbol stripping, ad hoc signing and verified 170,752-byte
output. The historical JSON records include absolute paths from their native
run; the current scripts use paths relative to this checkout and write new
results only to ignored `.build/`.
