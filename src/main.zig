const std = @import("std");
const bb = @import("blackboard.zig");
const lin = std.os.linux;

const default_watch_secs: u32 = 600;
const default_log_n: usize = 20;

const usage_text =
    \\bb — blackboard chat for agents and humans
    \\
    \\usage:
    \\  bb init                                   create .blackboard/ in cwd
    \\  bb post [-c chan] [-f who] [--re id] <text|->  post message (- reads stdin)
    \\  bb log [-c chan] [-n N | --all]           channel transcript (default general, last 20)
    \\  bb unread [-f who] [-c chan] [--ack]      unseen messages from others
    \\  bb ack [-f who] [-c chan]                 mark everything read
    \\  bb watch [-f who] [-c chan] [-t secs]     block until new mail (0 = forever)
    \\  bb channels                               list channels
    \\
    \\identity: -f or $BB_AGENT. root: nearest .blackboard/ upward from cwd, or $BB_ROOT.
    \\watch exits 0 when new mail was printed, 2 on timeout.
    \\
;

const Cmd = enum { init, post, log, unread, ack, channels, watch };

const Flag = enum { chan, from, re, n, t, ack, all, help };

const flag_map = std.StaticStringMap(Flag).initComptime(.{
    .{ "-c", .chan },
    .{ "-f", .from },
    .{ "--re", .re },
    .{ "-n", .n },
    .{ "-t", .t },
    .{ "--ack", .ack },
    .{ "--all", .all },
    .{ "-h", .help },
    .{ "--help", .help },
});

const Args = struct {
    cmd: []const u8,
    chan: ?[]const u8 = null,
    from: ?[]const u8 = null,
    re: ?[]const u8 = null,
    n: usize = default_log_n,
    t: u32 = default_watch_secs,
    ack: bool = false,
    all: bool = false,
    pos: ?[]const u8 = null,
};

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("bb: " ++ fmt ++ "\n", args);
    std.process.exit(1);
}

fn flagVal(argv: []const [:0]const u8, i: *usize, name: []const u8) []const u8 {
    i.* += 1;
    if (i.* >= argv.len) fatal("{s} requires a value", .{name});
    return argv[i.*];
}

fn parseArgs(argv: []const [:0]const u8) Args {
    if (argv.len < 2) {
        std.debug.print("{s}", .{usage_text});
        std.process.exit(1);
    }
    var a = Args{ .cmd = argv[1] };
    var i: usize = 2;
    while (i < argv.len) : (i += 1) {
        const arg = argv[i];
        if (flag_map.get(arg)) |flag| switch (flag) {
            .chan => a.chan = flagVal(argv, &i, "-c"),
            .from => a.from = flagVal(argv, &i, "-f"),
            .re => a.re = flagVal(argv, &i, "--re"),
            .n => {
                const v = flagVal(argv, &i, "-n");
                a.n = std.fmt.parseInt(usize, v, 10) catch fatal("-n: not a number: {s}", .{v});
            },
            .t => {
                const v = flagVal(argv, &i, "-t");
                a.t = std.fmt.parseInt(u32, v, 10) catch fatal("-t: not a number: {s}", .{v});
            },
            .ack => a.ack = true,
            .all => a.all = true,
            .help => {
                std.debug.print("{s}", .{usage_text});
                std.process.exit(0);
            },
        } else if (arg.len > 1 and arg[0] == '-') {
            fatal("unknown flag: {s}", .{arg});
        } else {
            if (a.pos != null) fatal("only one positional argument allowed (quote the message)", .{});
            a.pos = arg;
        }
    }
    return a;
}

fn identity(a: Args, env: *std.process.Environ.Map) []const u8 {
    const who = a.from orelse env.get("BB_AGENT") orelse
        fatal("identity unknown: pass -f <name> or set $BB_AGENT", .{});
    if (!bb.validName(who)) fatal("invalid identity: {s} (allowed [a-z0-9._-], no leading . or -)", .{who});
    return who;
}

const Root = struct { dir: std.Io.Dir, path: []const u8 };

fn openRoot(alloc: std.mem.Allocator, io: std.Io, env: *std.process.Environ.Map) !Root {
    const path = blk: {
        if (env.get("BB_ROOT")) |r| break :blk try std.fs.path.join(alloc, &.{ r, ".blackboard" });
        const cwd = try std.process.currentPathAlloc(io, alloc);
        break :blk bb.findRootFrom(alloc, io, cwd) catch |err| switch (err) {
            error.NoBlackboard => fatal("no .blackboard/ found upward from cwd (run `bb init` at the project root)", .{}),
            else => return err,
        };
    };
    const dir = std.Io.Dir.openDirAbsolute(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => fatal("no .blackboard/ at {s} (run `bb init`)", .{path}),
        else => return err,
    };
    return .{ .dir = dir, .path = path };
}

fn renderMsg(out: *std.Io.Writer, m: bb.Msg) !void {
    try out.print("── {s}  #{s}  {s}  id:{s}\n", .{ m.from, m.chan, m.at, m.id });
    if (m.re) |r| try out.print("   re:{s}\n", .{r});
    try out.print("{s}\n\n", .{m.body});
}

fn renderUnread(out: *std.Io.Writer, groups: []bb.ChanUnread) !void {
    for (groups) |g| {
        for (g.msgs) |m| try renderMsg(out, m);
    }
}

pub fn main(p: std.process.Init) !void {
    const alloc = p.arena.allocator();
    const io = p.io;
    const env = p.environ_map;

    var out_buf: [16384]u8 = undefined;
    var out_fw = std.Io.File.stdout().writerStreaming(io, &out_buf);
    const out = &out_fw.interface;

    var argv: std.ArrayList([:0]const u8) = .empty;
    var arg_it = p.minimal.args.iterate();
    while (arg_it.next()) |arg| try argv.append(alloc, arg);
    const a = parseArgs(argv.items);

    const cmd = std.meta.stringToEnum(Cmd, a.cmd) orelse {
        std.debug.print("{s}", .{usage_text});
        std.process.exit(1);
    };

    switch (cmd) {
        .init => {
            try bb.init(io, std.Io.Dir.cwd());
            const cwd = try std.process.currentPathAlloc(io, alloc);
            try out.print("initialized {s}/.blackboard\n", .{cwd});
        },
        .post, .log, .unread, .ack, .channels, .watch => {
            var root = try openRoot(alloc, io, env);
            defer root.dir.close(io);
            switch (cmd) {
                // handled by the outer .init arm; unreachable here
                .init => unreachable,
                .post => {
                    const who = identity(a, env);
                    const chan = a.chan orelse "general";
                    if (!bb.validName(chan)) fatal("invalid channel: {s}", .{chan});
                    const text = a.pos orelse fatal("post: message text required (or - for stdin)", .{});
                    const body = if (std.mem.eql(u8, text, "-"))
                        bb.slurp(alloc, io, std.Io.File.stdin(), bb.max_msg) catch |err| switch (err) {
                            error.TooBig => fatal("message exceeds {d} bytes", .{bb.max_msg}),
                            else => return err,
                        }
                    else
                        text;
                    const id = bb.post(alloc, io, root.dir, chan, who, a.re, body, ms(io), rand(io)) catch |err| switch (err) {
                        error.BadName => fatal("invalid name in chan={s} from={s} re={s}", .{ chan, who, a.re orelse "-" }),
                        error.BadMessage => fatal("empty message", .{}),
                        error.TooBig => fatal("message exceeds {d} bytes", .{bb.max_msg}),
                        else => return err,
                    };
                    try out.print("{s}\n", .{id});
                },
                .log => {
                    const chan = a.chan orelse "general";
                    const names = bb.list(alloc, io, root.dir, chan) catch |err| switch (err) {
                        error.FileNotFound => fatal("no such channel: {s}", .{chan}),
                        else => return err,
                    };
                    const start = if (a.all or names.len <= a.n) 0 else names.len - a.n;
                    for (names[start..]) |id| {
                        const m = bb.readMsg(alloc, io, root.dir, chan, id) catch |err| switch (err) {
                            error.BadMessage => fatal("malformed message file: channels/{s}/{s}{s}", .{ chan, id, bb.ext }),
                            else => return err,
                        };
                        try renderMsg(out, m);
                    }
                },
                .unread => {
                    const who = identity(a, env);
                    const groups = bb.unreadAll(alloc, io, root.dir, who, a.chan, a.ack) catch |err| switch (err) {
                        error.BadMessage => fatal("malformed message file in .blackboard/channels/", .{}),
                        else => return err,
                    };
                    try renderUnread(out, groups);
                },
                .ack => {
                    const who = identity(a, env);
                    try bb.ackAll(alloc, io, root.dir, who, a.chan);
                },
                .channels => {
                    for (try bb.channels(alloc, io, root.dir)) |c| try out.print("{s}\n", .{c});
                },
                .watch => {
                    try watch(alloc, io, env, root.dir, root.path, a, out);
                },
            }
        },
    }
    try out.flush();
}

/// Wall-clock milliseconds since the Unix epoch.
fn ms(io: std.Io) i64 {
    return std.Io.Clock.now(.real, io).toMilliseconds();
}

/// A random u16 for the id suffix.
fn rand(io: std.Io) u16 {
    var rb: [2]u8 = undefined;
    io.random(&rb);
    return std.mem.readInt(u16, &rb, .little);
}

fn inotifyInit() !i32 {
    const rc = lin.inotify_init1(0);
    return switch (std.posix.errno(rc)) {
        .SUCCESS => @intCast(rc),
        else => |e| std.posix.unexpectedErrno(e),
    };
}

fn inotifyAddWatch(fd: i32, pathz: [*:0]const u8, mask: u32) !void {
    const rc = lin.inotify_add_watch(fd, pathz, mask);
    return switch (std.posix.errno(rc)) {
        .SUCCESS => {},
        else => |e| std.posix.unexpectedErrno(e),
    };
}

/// Block until unseen mail exists (inotify), print it, exit 0. Exit 2 on timeout.
fn watch(alloc: std.mem.Allocator, io: std.Io, env: *std.process.Environ.Map, root: std.Io.Dir, root_path: []const u8, a: Args, out: *std.Io.Writer) !void {
    const who = identity(a, env);
    const infd = try inotifyInit();
    // cleanup: propagation impossible in defer; close cannot be recovered from
    defer _ = lin.close(infd);

    const chans_path = try std.fs.path.joinZ(alloc, &.{ root_path, "channels" });
    try inotifyAddWatch(infd, chans_path.ptr, lin.IN.CREATE | lin.IN.MOVED_TO);

    var watched = std.StringHashMap(void).init(alloc);
    const deadline: ?i64 = if (a.t == 0) null else ms(io) + @as(i64, a.t) * 1000;

    while (true) {
        for (try bb.channels(alloc, io, root)) |chan| {
            if (a.chan) |o| if (!std.mem.eql(u8, o, chan)) continue;
            if (watched.contains(chan)) continue;
            const p = try std.fs.path.joinZ(alloc, &.{ chans_path, chan });
            try inotifyAddWatch(infd, p.ptr, lin.IN.CREATE | lin.IN.MOVED_TO | lin.IN.ONLYDIR);
            try watched.put(chan, {});
        }

        const groups = try bb.unreadAll(alloc, io, root, who, a.chan, false);
        if (groups.len > 0) {
            try renderUnread(out, groups);
            try out.flush();
            return;
        }

        const timeout_ms: i32 = if (deadline) |d| blk: {
            const left = d - ms(io);
            if (left <= 0) {
                try out.flush();
                std.process.exit(2);
            }
            break :blk @intCast(@min(left, std.math.maxInt(i32)));
        } else -1;

        var fds = [_]std.posix.pollfd{.{ .fd = infd, .events = std.posix.POLL.IN, .revents = 0 }};
        const ready = try std.posix.poll(&fds, timeout_ms);
        if (ready == 0) {
            try out.flush();
            std.process.exit(2);
        }
        var evbuf: [4096]u8 align(@alignOf(lin.inotify_event)) = undefined;
        const n = try std.posix.read(infd, &evbuf);
        std.debug.assert(n > 0);
    }
}
