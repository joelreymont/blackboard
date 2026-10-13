# Blackboard focused follow-up review — accepted

An independent read-only follow-up checked four confirmed findings in the
complete macOS Habu port against the frozen source and the supplied native
regression results. It found no remaining blocker in that scope. The review
inspected both 135/135 per-case results without claiming an independent rerun.

| Repaired behavior | Acceptance evidence |
| --- | --- |
| Watched channel inode moves inside or beyond the board | `main.f:1090–1104` and `tests/reference/main.zig:315–363` check the event parent by device and inode. First registration by channel name stays permanent. Native regressions waited through the move and cursor reset, then printed the new message in the moved inode. |
| ELOOP diagnostics | `main.f:419,461,471,888,922` maps native ELOOP to `error: SymLinkLoop` for root discovery or override, channel stat, cursor read and cursor write. Exact stderr regressions passed. |
| Execute-only nearest root | `main.f:403–412` requires read access to the entered directory and closes its temporary descriptor. Both mode-0111 cases reported `error: AccessDenied`. |
| Finite clamped timeout | `main.f:1151–1181` and `tests/reference/main.zig:429–453` retain a logical deadline across irrelevant callbacks, returning exit 2 at expiry. Both unrelated-event regressions expired in about 1.01–1.03 seconds. |

The 135-case results also passed same-inode edit suppression, new hardlink
names, delete/recreate, rename-back, settled channel replacement, and 70
channels under `RLIMIT_NOFILE=64`. The approximately 24.85-day clamp and
unbounded segment renewal were checked in source; no multi-week test ran.
The accepted scope does not claim event-by-event equivalence across every
native filesystem race.

Frozen SHA-256: `main.f`
`a9296968b1cf138d5766340e33d478427f46822f8dc5949e6eb4d0ae72c4f540`,
`tests/reference/main.zig`
`5988730e7552e26092e7f6a9b89ae6143829d76aed19da55df1f45d10f9c837b`,
`tests/reference/blackboard.zig`
`dffac7a1fef988d922cb1a3d0a3359ae10a5f3d29140fb32ae0f2611ad54840b`.
The preserved [ordinary result](full-parity-small.json) has SHA-256
`24a87b876a54ff4e25d01f3001c1fd0a88db48ab9c43d63058f7d1704b272d9e`;
the [minimal result](full-parity-smallest.json) has SHA-256
`766cc660108dab01cc15c5e940e2fc8c79f032a586274f4290875208705b0e6a`.
