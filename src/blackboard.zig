const std = @import("std");

pub const max_msg = 1 << 20;
pub const max_name = 64;
pub const ext = ".md";

pub const Msg = struct {
    id: []const u8,
    chan: []const u8,
    from: []const u8,
    at: []const u8,
    re: ?[]const u8,
    body: []const u8,
};

pub const ChanUnread = struct {
    chan: []const u8,
    msgs: []Msg,
};

pub fn validName(s: []const u8) bool {
    if (s.len == 0 or s.len > max_name) return false;
    if (s[0] == '.' or s[0] == '-') return false;
    for (s) |c| switch (c) {
        'a'...'z', '0'...'9', '-', '_', '.' => {},
        else => return false,
    };
    return true;
}

const TsParts = struct { y: u16, mo: u8, d: u8, h: u8, mi: u8, s: u8, ms: u16 };

fn tsParts(ms_total: i64) TsParts {
    const secs: u64 = @intCast(@divFloor(ms_total, 1000));
    const msec: u16 = @intCast(@mod(ms_total, 1000));
    const es = std.time.epoch.EpochSeconds{ .secs = secs };
    const yd = es.getEpochDay().calculateYearDay();
    const md = yd.calculateMonthDay();
    const ds = es.getDaySeconds();
    return .{
        .y = yd.year,
        .mo = md.month.numeric(),
        .d = @as(u8, md.day_index) + 1,
        .h = ds.getHoursIntoDay(),
        .mi = ds.getMinutesIntoHour(),
        .s = ds.getSecondsIntoMinute(),
        .ms = msec,
    };
}

pub fn fmtId(alloc: std.mem.Allocator, ms: i64, from: []const u8, rand: u16) ![]u8 {
    const p = tsParts(ms);
    return std.fmt.allocPrint(alloc, "{d:0>4}{d:0>2}{d:0>2}-{d:0>2}{d:0>2}{d:0>2}.{d:0>3}-{s}-{x:0>4}", .{ p.y, p.mo, p.d, p.h, p.mi, p.s, p.ms, from, rand });
}

pub fn fmtIso(alloc: std.mem.Allocator, ms: i64) ![]u8 {
    const p = tsParts(ms);
    return std.fmt.allocPrint(alloc, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}Z", .{ p.y, p.mo, p.d, p.h, p.mi, p.s, p.ms });
}

pub fn init(io: std.Io, dir: std.Io.Dir) !void {
    try dir.createDirPath(io, ".blackboard/channels/general");
    try dir.createDirPath(io, ".blackboard/cursors");
    try dir.createDirPath(io, ".blackboard/tmp");
}

/// Walk up from `start_abs` looking for a `.blackboard` dir; returns its absolute path.
pub fn findRootFrom(alloc: std.mem.Allocator, io: std.Io, start_abs: []const u8) ![]u8 {
    var dir_path = start_abs;
    while (true) {
        const cand = try std.fs.path.join(alloc, &.{ dir_path, ".blackboard" });
        if (std.Io.Dir.accessAbsolute(io, cand, .{})) |_| {
            return cand;
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        }
        dir_path = std.fs.path.dirname(dir_path) orelse return error.NoBlackboard;
    }
}

/// Read an open file fully into memory, up to `limit` bytes. Used for stdin.
pub fn slurp(alloc: std.mem.Allocator, io: std.Io, f: std.Io.File, limit: usize) ![]u8 {
    var buf: [16384]u8 = undefined;
    var fr = f.readerStreaming(io, &buf);
    return fr.interface.allocRemaining(alloc, .limited(limit)) catch |err| switch (err) {
        error.StreamTooLong => error.TooBig,
        else => |e| return e,
    };
}

/// Atomically publish a message: write to tmp/, rename into the channel dir.
pub fn post(alloc: std.mem.Allocator, io: std.Io, root: std.Io.Dir, chan: []const u8, from: []const u8, re: ?[]const u8, body_raw: []const u8, ms: i64, rand: u16) ![]u8 {
    if (!validName(chan) or !validName(from)) return error.BadName;
    if (re) |r| if (!validName(r)) return error.BadName;
    const body = std.mem.trim(u8, body_raw, " \t\r\n");
    if (body.len == 0) return error.BadMessage;
    if (body.len > max_msg) return error.TooBig;
    const id = try fmtId(alloc, ms, from, rand);
    const at = try fmtIso(alloc, ms);
    const content = if (re) |r|
        try std.fmt.allocPrint(alloc, "---\nfrom: {s}\nat: {s}\nre: {s}\n---\n\n{s}\n", .{ from, at, r, body })
    else
        try std.fmt.allocPrint(alloc, "---\nfrom: {s}\nat: {s}\n---\n\n{s}\n", .{ from, at, body });
    const chan_path = try std.fs.path.join(alloc, &.{ "channels", chan });
    try root.createDirPath(io, chan_path);
    try root.createDirPath(io, "tmp");
    const fname = try std.fmt.allocPrint(alloc, "{s}{s}", .{ id, ext });
    const tmp_path = try std.fs.path.join(alloc, &.{ "tmp", fname });
    try root.writeFile(io, .{ .sub_path = tmp_path, .data = content });
    var td = try root.openDir(io, "tmp", .{});
    defer td.close(io);
    var cd = try root.openDir(io, chan_path, .{});
    defer cd.close(io);
    try td.rename(fname, cd, fname, io);
    return id;
}

/// Message ids in a channel, lexicographically sorted (= chronological).
pub fn list(alloc: std.mem.Allocator, io: std.Io, root: std.Io.Dir, chan: []const u8) ![][]const u8 {
    const chan_path = try std.fs.path.join(alloc, &.{ "channels", chan });
    var d = try root.openDir(io, chan_path, .{ .iterate = true });
    defer d.close(io);
    var names: std.ArrayList([]const u8) = .empty;
    var it = d.iterate();
    while (try it.next(io)) |e| {
        if (e.kind != .file) continue;
        if (!std.mem.endsWith(u8, e.name, ext)) continue;
        try names.append(alloc, try alloc.dupe(u8, e.name[0 .. e.name.len - ext.len]));
    }
    std.mem.sort([]const u8, names.items, {}, strLt);
    return names.items;
}

fn strLt(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

pub fn channels(alloc: std.mem.Allocator, io: std.Io, root: std.Io.Dir) ![][]const u8 {
    var d = try root.openDir(io, "channels", .{ .iterate = true });
    defer d.close(io);
    var names: std.ArrayList([]const u8) = .empty;
    var it = d.iterate();
    while (try it.next(io)) |e| {
        if (e.kind != .directory) continue;
        try names.append(alloc, try alloc.dupe(u8, e.name));
    }
    std.mem.sort([]const u8, names.items, {}, strLt);
    return names.items;
}

pub fn readMsg(alloc: std.mem.Allocator, io: std.Io, root: std.Io.Dir, chan: []const u8, id: []const u8) !Msg {
    const p = try std.fmt.allocPrint(alloc, "channels/{s}/{s}{s}", .{ chan, id, ext });
    const data = try root.readFileAlloc(io, p, alloc, .limited(max_msg));
    return parse(data, id, chan);
}

pub fn parse(data: []const u8, id: []const u8, chan: []const u8) !Msg {
    const open = "---\n";
    const close_mark = "\n---\n";
    if (!std.mem.startsWith(u8, data, open)) return error.BadMessage;
    const close = std.mem.indexOfPos(u8, data, open.len, close_mark) orelse return error.BadMessage;
    var from: ?[]const u8 = null;
    var at: ?[]const u8 = null;
    var re: ?[]const u8 = null;
    var lines = std.mem.splitScalar(u8, data[open.len..close], '\n');
    while (lines.next()) |line| {
        const sep = std.mem.indexOf(u8, line, ": ") orelse return error.BadMessage;
        const k = line[0..sep];
        const v = line[sep + 2 ..];
        if (std.mem.eql(u8, k, "from")) {
            from = v;
        } else if (std.mem.eql(u8, k, "at")) {
            at = v;
        } else if (std.mem.eql(u8, k, "re")) {
            re = v;
        } else {
            return error.BadMessage;
        }
    }
    const rest = data[close + close_mark.len ..];
    const body_full = if (std.mem.startsWith(u8, rest, "\n")) rest[1..] else rest;
    return .{
        .id = id,
        .chan = chan,
        .from = from orelse return error.BadMessage,
        .at = at orelse return error.BadMessage,
        .re = re,
        .body = std.mem.trimEnd(u8, body_full, "\n"),
    };
}

pub fn readCursor(alloc: std.mem.Allocator, io: std.Io, root: std.Io.Dir, agent: []const u8, chan: []const u8) !?[]const u8 {
    const p = try std.fs.path.join(alloc, &.{ "cursors", agent, chan });
    const data = root.readFileAlloc(io, p, alloc, .limited(4 * max_name)) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => |e| return e,
    };
    return std.mem.trimEnd(u8, data, "\n");
}

pub fn writeCursor(alloc: std.mem.Allocator, io: std.Io, root: std.Io.Dir, agent: []const u8, chan: []const u8, id: []const u8) !void {
    const dirp = try std.fs.path.join(alloc, &.{ "cursors", agent });
    try root.createDirPath(io, dirp);
    const cursor_path = try std.fs.path.join(alloc, &.{ dirp, chan });
    try root.writeFile(io, .{ .sub_path = cursor_path, .data = id });
}

/// Unseen messages from other participants, grouped by channel.
/// With `ack`, cursors advance to the newest id per scanned channel (own messages included).
pub fn unreadAll(alloc: std.mem.Allocator, io: std.Io, root: std.Io.Dir, agent: []const u8, only: ?[]const u8, ack: bool) ![]ChanUnread {
    if (!validName(agent)) return error.BadName;
    var out: std.ArrayList(ChanUnread) = .empty;
    for (try channels(alloc, io, root)) |chan| {
        if (only) |o| if (!std.mem.eql(u8, o, chan)) continue;
        const names = try list(alloc, io, root, chan);
        if (names.len == 0) continue;
        const cur = try readCursor(alloc, io, root, agent, chan);
        var msgs: std.ArrayList(Msg) = .empty;
        for (names) |id| {
            if (cur) |c| {
                if (!std.mem.lessThan(u8, c, id)) continue;
            }
            const m = try readMsg(alloc, io, root, chan, id);
            if (std.mem.eql(u8, m.from, agent)) continue;
            try msgs.append(alloc, m);
        }
        if (ack) try writeCursor(alloc, io, root, agent, chan, names[names.len - 1]);
        if (msgs.items.len > 0) try out.append(alloc, .{ .chan = chan, .msgs = msgs.items });
    }
    return out.items;
}

pub fn ackAll(alloc: std.mem.Allocator, io: std.Io, root: std.Io.Dir, agent: []const u8, only: ?[]const u8) !void {
    if (!validName(agent)) return error.BadName;
    for (try channels(alloc, io, root)) |chan| {
        if (only) |o| if (!std.mem.eql(u8, o, chan)) continue;
        const names = try list(alloc, io, root, chan);
        if (names.len == 0) continue;
        try writeCursor(alloc, io, root, agent, chan, names[names.len - 1]);
    }
}

const t = std.testing;

test "validName" {
    try t.expect(validName("general"));
    try t.expect(validName("dots-123"));
    try t.expect(validName("20260722-134502.123-claude-7f3a"));
    try t.expect(!validName(""));
    try t.expect(!validName(".hidden"));
    try t.expect(!validName("-dash"));
    try t.expect(!validName("Upper"));
    try t.expect(!validName("a/b"));
}

test "id and iso formatting at epoch boundaries" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    try t.expectEqualStrings("19700101-000000.000-claude-abcd", try fmtId(alloc, 0, "claude", 0xabcd));
    try t.expectEqualStrings("1970-01-02T01:01:01.001Z", try fmtIso(alloc, 86_400_000 + 3_661_001));
    const early = try fmtId(alloc, 1000, "codex", 0xffff);
    const late = try fmtId(alloc, 2000, "codex", 0x0000);
    try t.expect(std.mem.lessThan(u8, early, late));
}

test "parse rejects malformed frontmatter" {
    try t.expectError(error.BadMessage, parse("no frontmatter", "x", "general"));
    try t.expectError(error.BadMessage, parse("---\nfrom: a\n---\n\nbody\n", "x", "general"));
    try t.expectError(error.BadMessage, parse("---\nfrom: a\nat: b\nbogus: c\n---\n\nbody\n", "x", "general"));
    try t.expectError(error.BadMessage, parse("---\nfrom a\nat: b\n---\n\nbody\n", "x", "general"));
}

test "body may contain frontmatter-like lines" {
    const m = try parse("---\nfrom: joel\nat: 2026-07-22T00:00:00.000Z\n---\n\n---\nfake: fm\n---\n", "x", "general");
    try t.expectEqualStrings("---\nfake: fm\n---", m.body);
}

test "post, list, readMsg, unread, ack round trip" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = t.io;
    var tmp = t.tmpDir(.{});
    defer tmp.cleanup();
    try init(io, tmp.dir);
    var root = try tmp.dir.openDir(io, ".blackboard", .{});
    defer root.close(io);

    const id1 = try post(alloc, io, root, "general", "codex", null, "hello claude\n", 1000, 1);
    const id2 = try post(alloc, io, root, "general", "claude", id1, "hi codex", 2000, 2);
    const names = try list(alloc, io, root, "general");
    try t.expectEqual(@as(usize, 2), names.len);
    try t.expectEqualStrings(id1, names[0]);
    try t.expectEqualStrings(id2, names[1]);

    const m = try readMsg(alloc, io, root, "general", id2);
    try t.expectEqualStrings("claude", m.from);
    try t.expectEqualStrings("hi codex", m.body);
    try t.expectEqualStrings(id1, m.re.?);

    const un1 = try unreadAll(alloc, io, root, "claude", null, false);
    try t.expectEqual(@as(usize, 1), un1.len);
    try t.expectEqual(@as(usize, 1), un1[0].msgs.len);
    try t.expectEqualStrings(id1, un1[0].msgs[0].id);

    try ackAll(alloc, io, root, "claude", null);
    try t.expectEqual(@as(usize, 0), (try unreadAll(alloc, io, root, "claude", null, false)).len);

    const un2 = try unreadAll(alloc, io, root, "codex", null, true);
    try t.expectEqual(@as(usize, 1), un2.len);
    try t.expectEqualStrings(id2, un2[0].msgs[0].id);
    try t.expectEqual(@as(usize, 0), (try unreadAll(alloc, io, root, "codex", null, false)).len);
}

test "unread respects channel filter and posting creates channels" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = t.io;
    var tmp = t.tmpDir(.{});
    defer tmp.cleanup();
    try init(io, tmp.dir);
    var root = try tmp.dir.openDir(io, ".blackboard", .{});
    defer root.close(io);

    _ = try post(alloc, io, root, "dots-9", "codex", null, "claiming dots-9", 1000, 1);
    _ = try post(alloc, io, root, "general", "codex", null, "hi", 2000, 2);
    const only = try unreadAll(alloc, io, root, "claude", "dots-9", false);
    try t.expectEqual(@as(usize, 1), only.len);
    try t.expectEqualStrings("dots-9", only[0].chan);
    const chans = try channels(alloc, io, root);
    try t.expectEqual(@as(usize, 2), chans.len);
    try t.expectEqualStrings("dots-9", chans[0]);
    try t.expectEqualStrings("general", chans[1]);
}

test "findRootFrom walks up to nearest .blackboard" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = t.io;
    var tmp = t.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "proj/.blackboard");
    try tmp.dir.createDirPath(io, "proj/a/b");
    const cwd = try std.process.currentPathAlloc(io, alloc);
    const base = try std.fs.path.join(alloc, &.{ cwd, ".zig-cache", "tmp", &tmp.sub_path });
    const start = try std.fs.path.join(alloc, &.{ base, "proj", "a", "b" });
    const found = try findRootFrom(alloc, io, start);
    const want = try std.fs.path.join(alloc, &.{ base, "proj", ".blackboard" });
    try t.expectEqualStrings(want, found);
}
