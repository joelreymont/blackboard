const std = @import("std");
const bb = @import("blackboard.zig");
// Linux inotify below is adapted to macOS FSEvents for this isolated reference.

const default_watch_secs: u32 = 600;
const default_log_n: usize = 20;

const usage_text =
    \\bb — blackboard chat for agents and humans
    \\
    \\usage:
    \\  bb init                                   create .blackboard/ in cwd
    \\  bb post [-c chan] [-f who] [--re id] <text|->  post message (- reads stdin)
    \\  bb log [-c chan] [-n N | --all] [--since d] [--md]  transcript (d = today | YYYY-MM-DD, UTC)
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

const Flag = enum { chan, from, re, n, t, ack, all, md, since, help };

const flag_map = std.StaticStringMap(Flag).initComptime(.{
    .{ "-c", .chan },
    .{ "-f", .from },
    .{ "--re", .re },
    .{ "-n", .n },
    .{ "-t", .t },
    .{ "--ack", .ack },
    .{ "--all", .all },
    .{ "--md", .md },
    .{ "--since", .since },
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
    md: bool = false,
    since: ?[]const u8 = null,
    n_set: bool = false,
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
                a.n_set = true;
            },
            .t => {
                const v = flagVal(argv, &i, "-t");
                a.t = std.fmt.parseInt(u32, v, 10) catch fatal("-t: not a number: {s}", .{v});
            },
            .ack => a.ack = true,
            .all => a.all = true,
            .md => a.md = true,
            .since => a.since = flagVal(argv, &i, "--since"),
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
                    const cut: ?[]u8 = if (a.since) |s|
                        bb.cutoffFromArg(alloc, s, ms(io)) catch |err| switch (err) {
                            error.BadDate => fatal("--since: want today or YYYY-MM-DD (UTC): {s}", .{s}),
                            else => return err,
                        }
                    else
                        null;
                    var kept: std.ArrayList([]const u8) = .empty;
                    for (names) |id| {
                        if (cut) |c| if (std.mem.lessThan(u8, id, c)) continue;
                        try kept.append(alloc, id);
                    }
                    const ids = kept.items;
                    const whole = a.all or (a.since != null and !a.n_set);
                    const start = if (whole or ids.len <= a.n) 0 else ids.len - a.n;
                    var msgs: std.ArrayList(bb.Msg) = .empty;
                    for (ids[start..]) |id| {
                        const m = bb.readMsg(alloc, io, root.dir, chan, id) catch |err| switch (err) {
                            error.BadMessage => fatal("malformed message file: channels/{s}/{s}{s}", .{ chan, id, bb.ext }),
                            else => return err,
                        };
                        try msgs.append(alloc, m);
                    }
                    if (a.md)
                        try bb.renderMd(out, chan, msgs.items)
                    else
                        for (msgs.items) |m| try renderMsg(out, m);
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
                    try watch(alloc, io, env, root.dir, a, out);
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

// FSEvents observes the filesystem tree with one stream. The board itself is
// always read through its opened Dir, including after a rename across parents.
const CFRef = ?*anyopaque;
const FSEventCallback = *const fn (CFRef, CFRef, usize, CFRef, CFRef, CFRef) callconv(.c) void;
const FSEventStreamContext = extern struct {
    version: isize,
    info: CFRef,
    retain: CFRef,
    release: CFRef,
    copy_description: CFRef,
};
extern "c" fn CFStringCreateWithCString(CFRef, [*:0]const u8, u32) CFRef;
extern "c" fn CFArrayCreate(CFRef, [*]const CFRef, isize, CFRef) CFRef;
extern "c" fn CFRelease(CFRef) void;
extern "c" fn CFRunLoopGetCurrent() CFRef;
extern "c" fn CFRunLoopRunInMode(CFRef, f64, bool) i32;
extern "c" fn FSEventStreamCreate(CFRef, FSEventCallback, *const FSEventStreamContext, CFRef, u64, f64, u32) CFRef;
extern "c" fn FSEventStreamScheduleWithRunLoop(CFRef, CFRef, CFRef) void;
extern "c" fn FSEventStreamStart(CFRef) bool;
extern "c" fn FSEventStreamStop(CFRef) void;
extern "c" fn FSEventStreamInvalidate(CFRef) void;
extern "c" fn FSEventStreamRelease(CFRef) void;
extern "c" fn stat([*:0]const u8, *std.c.Stat) c_int;
extern "c" fn fstat(c_int, *std.c.Stat) c_int;
extern "c" fn fstatat(c_int, [*:0]const u8, *std.c.Stat, c_int) c_int;

const WatchIdentity = struct { dev: i32, ino: u64 };
const WatchState = struct {
    alloc: std.mem.Allocator,
    channels: WatchIdentity,
    watched: *std.StringHashMap(WatchIdentity),
    seen: *std.StringHashMap(WatchIdentity),
    err: ?anyerror = null,
    wake: bool = false,
};

fn identityOf(s: std.c.Stat) WatchIdentity {
    return .{ .dev = s.dev, .ino = s.ino };
}

fn sameIdentity(a: WatchIdentity, b: WatchIdentity) bool {
    return a.dev == b.dev and a.ino == b.ino;
}

fn fileKey(alloc: std.mem.Allocator, parent: WatchIdentity, name: []const u8) ![]const u8 {
    return alloc.print("{d}:{d}:{s}", .{ parent.dev, parent.ino, name });
}

fn fsEvent(_: CFRef, info: CFRef, count: usize, paths: CFRef, flags: CFRef, _: CFRef) callconv(.c) void {
    const state: *WatchState = @ptrCast(@alignCast(info.?));
    const event_paths: [*]const [*:0]const u8 = @ptrCast(@alignCast(paths.?));
    const event_flags: [*]const u32 = @ptrCast(@alignCast(flags.?));
    var parent_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    for (0..count) |i| {
        // FSEvents reports both sides of a rename; an inotify MOVED_TO
        // corresponds only to a destination that still exists.
        if (event_flags[i] & (0x100 | 0x800) == 0) continue;
        const event_path = std.mem.span(event_paths[i]);
        const slash = std.mem.findScalarLast(u8, event_path, '/') orelse continue;
        if (slash + 1 >= parent_buf.len) continue;
        @memcpy(parent_buf[0..slash], event_path[0..slash]);
        parent_buf[slash] = 0;
        var parent_stat: std.c.Stat = undefined;
        var item_stat: std.c.Stat = undefined;
        if (stat(@ptrCast(&parent_buf), &parent_stat) != 0 or stat(event_paths[i], &item_stat) != 0) continue;
        const parent_id = identityOf(parent_stat);
        if (sameIdentity(parent_id, state.channels)) {
            state.wake = true;
            return;
        }
        var it = state.watched.valueIterator();
        while (it.next()) |id| {
            if (sameIdentity(parent_id, id.*)) {
                var key_buf: [std.Io.Dir.max_path_bytes + 64]u8 = undefined;
                const key = std.mem.print(&key_buf, "{d}:{d}:{s}", .{
                    parent_id.dev, parent_id.ino, event_path[slash + 1 ..],
                }) catch continue;
                const item_id = identityOf(item_stat);
                if (state.seen.getPtr(key)) |known| {
                    const same = sameIdentity(known.*, item_id);
                    known.* = item_id;
                    if (same and event_flags[i] & 0x800 == 0) continue;
                } else {
                    const owned = state.alloc.dupe(u8, key) catch |err| {
                        state.err = err;
                        state.wake = true;
                        return;
                    };
                    state.seen.put(owned, item_id) catch |err| {
                        state.err = err;
                        state.wake = true;
                        return;
                    };
                }
                state.wake = true;
                return;
            }
        }
    }
}

/// Block until unseen mail exists (FSEvents), print it, exit 0. Exit 2 on timeout.
fn watch(alloc: std.mem.Allocator, io: std.Io, env: *std.process.Environ.Map, root: std.Io.Dir, a: Args, out: *std.Io.Writer) !void {
    const who = identity(a, env);
    var channels_dir = try root.openDir(io, "channels", .{});
    defer channels_dir.close(io);
    var channels_stat: std.c.Stat = undefined;
    if (fstat(channels_dir.handle, &channels_stat) != 0) return error.WatchAddFailed;
    var watched = std.StringHashMap(WatchIdentity).init(alloc);
    defer watched.deinit();
    var seen = std.StringHashMap(WatchIdentity).init(alloc);
    defer seen.deinit();
    var state: WatchState = .{
        .alloc = alloc, .channels = identityOf(channels_stat),
        .watched = &watched, .seen = &seen,
    };
    const path = CFStringCreateWithCString(null, "/", 0x08000100) orelse return error.WatchCreateFailed;
    defer CFRelease(path);
    const path_values = [_]CFRef{path};
    const paths = CFArrayCreate(null, &path_values, 1, null) orelse return error.WatchCreateFailed;
    defer CFRelease(paths);
    const mode = CFStringCreateWithCString(null, "kCFRunLoopDefaultMode", 0x08000100) orelse return error.WatchCreateFailed;
    defer CFRelease(mode);
    const context: FSEventStreamContext = .{
        .version = 0, .info = &state, .retain = null, .release = null, .copy_description = null,
    };
    const stream = FSEventStreamCreate(null, fsEvent, &context, paths, std.math.maxInt(u64), 0.05, 0x14) orelse return error.WatchCreateFailed;
    defer {
        FSEventStreamStop(stream);
        FSEventStreamInvalidate(stream);
        FSEventStreamRelease(stream);
    }
    FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetCurrent(), mode);
    if (!FSEventStreamStart(stream)) return error.WatchStartFailed;
    const deadline: ?i64 = if (a.t == 0) null else ms(io) + @as(i64, a.t) * 1000;

    while (true) {
        for (try bb.channels(alloc, io, root)) |chan| {
            if (a.chan) |only| if (!std.mem.eql(u8, only, chan)) continue;
            if (watched.contains(chan)) continue;
            const chan_path = try std.fs.path.join(alloc, &.{ "channels", chan });
            var chan_dir = try root.openDir(io, chan_path, .{ .iterate = true });
            defer chan_dir.close(io);
            var chan_stat: std.c.Stat = undefined;
            if (fstat(chan_dir.handle, &chan_stat) != 0) return error.WatchAddFailed;
            const parent_id = identityOf(chan_stat);
            var entries = chan_dir.iterate();
            while (try entries.next(io)) |entry| {
                const name = try alloc.dupeSentinel(u8, entry.name, 0);
                var item_stat: std.c.Stat = undefined;
                if (fstatat(chan_dir.handle, name, &item_stat, 0) != 0) continue;
                try seen.put(try fileKey(alloc, parent_id, entry.name), identityOf(item_stat));
            }
            try watched.put(chan, parent_id);
        }
        const groups = try bb.unreadAll(alloc, io, root, who, a.chan, false);
        if (groups.len > 0) {
            try renderUnread(out, groups);
            try out.flush();
            return;
        }

        const segment_end = ms(io) + std.math.maxInt(i32);
        var poll_deadline = if (deadline) |d| @min(d, segment_end) else segment_end;
        while (!state.wake) {
            const poll_ms = poll_deadline - ms(io);
            if (poll_ms <= 0) {
                if (deadline == null) {
                    poll_deadline = ms(io) + std.math.maxInt(i32);
                    continue;
                }
                try out.flush();
                std.process.exit(2);
            }
            const result = CFRunLoopRunInMode(mode, @as(f64, @floatFromInt(poll_ms)) / 1000.0, true);
            if (result == 1 or result == 2) return error.WatchStartFailed;
            if (result == 3) {
                if (deadline == null) {
                    poll_deadline = ms(io) + std.math.maxInt(i32);
                    continue;
                }
                try out.flush();
                std.process.exit(2);
            }
        }
        if (state.err) |err| return err;
        state.wake = false;
    }
}
