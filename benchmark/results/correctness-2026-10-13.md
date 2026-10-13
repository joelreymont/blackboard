# Blackboard correctness repairs — 2026-10-13

All confirmed findings from the independent correctness audit and its repair
review are fixed. The final macOS arm64 build passed the required comparison,
focused regressions, and independent review. This replaces the earlier readiness
judgment based on parity alone. It is not a claim that every failure schedule has
been tested.

## Fixed behavior

| Original severity | Reproducer | Corrected result |
| --- | --- | --- |
| High | Symlink an init/post/ack destination directory to a sentinel directory. | Reject the link; preserve the target. |
| High | Remove channel search permission, then log/unread/ack. | Report failure instead of silently hiding mail or pretending to acknowledge it. |
| Medium | Deny message, directory, staging, or destination access. | Return a useful failure diagnostic, including native watch registration. |
| Medium | Supply exactly 1 MiB on nonblocking stdin without EOF. | Reject the incomplete read; publish nothing. |
| High, shared with Zig | Post a valid body near 1 MiB, then read it. | Allow the generated frontmatter as well as the full body. |
| Medium, shared with Zig | Acknowledge a high ID, then publish a lower ID. | Deliver the later message using exact acknowledged-ID membership. |
| Medium, shared with Zig | Link Alice's cursor file to Bob's cursor. | Reject the link; preserve both ownership and target bytes. |
| Low, shared with Zig | Read a message with an unknown frontmatter key. | Name the offending file in log, unread, and watch errors. |
| High, shared with Zig | Run unread --ack with valid alpha mail and malformed later general mail, or with failed stdout. | Do not acknowledge any undelivered output. |
| Medium, found during repair review | Acknowledge a 255-character imported channel; use a FIFO cursor. | Use a short staging basename; reject the FIFO promptly with its filename. |

Cursor commits merge captured IDs under an agent-directory lock, write an
exclusive temporary file in that directory, and publish through atomic rename.
Concurrent commits retain their union. Failed partial writes preserve the prior
cursor and remove their staging file. A process killed during staging preserves
the prior cursor, though its interrupted temporary file can remain.

The v2 cursor is `NUL bb-cursor-v2 NUL` followed by sorted, unique,
NUL-terminated ID records. It supports empty, newline-containing, long, and
Unicode IDs. Legacy cursors retain the 255-byte limit and acknowledge only their
named ID. Other historical mail can replay once; the next acknowledgement writes
v2. Old executables must not be alternated with v2 cursors. Acknowledged history
grows, including IDs of removed messages. Watch never writes or upgrades cursors.

## Verification

- Pinned `sh build.sh` succeeded with Habu `c53b4d2c`; no compiler changes.
- `sh tests/build-reference.sh` succeeded. The preserved Zig implementation and
  its existing macOS watch adaptation remain unchanged.
- `python3 tests/differential.py .build/bb-zig-reference bin/bb`: **135/135**.
  Intentional cursor, read-limit, and diagnostic differences have explicit
  assertions. Other output, status, and persisted state remain compared.
- `python3 tests/regressions.py bin/bb --watch`: **39/39**. Permanent tests cover
  the concrete failures, including a blocked-output concurrent cursor merge and
  a partial staging write forced with `RLIMIT_FSIZE`.
- Independent Astra review checked all changed source hunks, affected callers,
  tests, and docs. It found three additional issues, all fixed. Its focused
  follow-up independently passed **8/8** checks with no remaining finding.
- Extended isolated checks: **26/26** across repaired Habu and frozen Zig,
  including 48 posts with up to eight writers in flight, complete publication,
  directory moves/replacements, filters, cancellation/restart, and a 30-second
  idle native watch.
- A 2,400-message, 13-channel store produced identical rendered output against
  Zig (3,116,490 unread bytes). Every cursor was independently checked against
  its expected format and exact IDs; all message bytes stayed unchanged.
- Killing an acknowledgement during staging with `SIGXFSZ` preserved the old
  cursor and kept all 20 new messages unread. A subsequent acknowledgement
  succeeded. Ignoring that signal instead exercised ordinary short-write/error
  cleanup in the permanent regression suite.

The accompanying [machine-readable record](correctness-2026-10-13.json) names
the tested source, binaries, and results. The installed executable's hash stayed
unchanged. No installation or push was performed.

## Scope limits

All test stores used synthetic HOME and explicit private BB_ROOT; the dedicated
upward-discovery cases intentionally unset BB_ROOT inside isolated trees. No live
stores were mutated. A bounded search found no real stores to snapshot, so there
is no real-store migration claim. Native FSEvents tests required host access and
were not counted as passing inside the restricted filesystem sandbox.

No forced random-ID collision, power-loss durability, full-disk condition, or
multi-hour watch/resource-growth test was performed. Atomic rename establishes
visibility, not an fsync-based power-loss guarantee. The preserved Zig branch is
the CLI comparison baseline; its macOS adapter is not proof of Linux event
equivalence. The installed Zig executable's exact source revision is unknown.
