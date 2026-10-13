#!/usr/bin/env python3
"""Behavioral regressions for Blackboard fixes, on disposable local boards.

Run ``python3 tests/regressions.py bin/bb`` from the repository root. Add
``--watch`` on a host where native FSEvents access is available. Every child
gets a synthetic HOME and an explicit BB_ROOT; fixtures stay in .build/.
"""

import argparse
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import re
import resource
import select
import signal
import stat
import socket
import subprocess
import tempfile
import time


MAX_BODY = 1 << 20
ID = re.compile(rb"\d{8}-\d{6}\.\d{3}-[a-z0-9._-]+-[0-9a-f]{4}\n")
STAMP = "20261013-120000.000"
CURSOR_MAGIC = b"\x00bb-cursor-v2\x00"


def require(condition, detail):
    if not condition:
        raise AssertionError(detail)


class Suite:
    def __init__(self, binary, base):
        self.binary = binary
        self.base = base
        self.total = 0
        self.failed = 0

    def case(self, name, fn):
        self.total += 1
        try:
            fn()
        except Exception as error:
            self.failed += 1
            print(f"FAIL {name}: {error}", flush=True)
        else:
            print(f"PASS {name}", flush=True)

    def root(self, name, *, bare=False):
        root = self.base / name
        root.mkdir()
        (root / "home").mkdir()
        if not bare:
            board = root / ".blackboard"
            for part in ("channels/general", "cursors", "tmp"):
                (board / part).mkdir(parents=True)
        return root

    def env(self, root):
        return {"HOME": str(root / "home"), "BB_ROOT": str(root),
                "BB_AGENT": "reader", "PATH": os.environ.get("PATH", "/usr/bin:/bin")}

    def call(self, root, *args, data=None, timeout=8):
        return subprocess.run([str(self.binary), *args], cwd=root,
                              env=self.env(root), input=data,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              timeout=timeout)

    @staticmethod
    def ok(result):
        require(result.returncode == 0 and result.stderr == b"",
                f"expected success: rc={result.returncode}, stderr={result.stderr[:300]!r}")
        return result

    @staticmethod
    def denied(result, error="AccessDenied"):
        require(result.returncode == 1 and result.stdout == b"" and
                error.encode() in result.stderr,
                f"expected {error}: rc={result.returncode}, "
                f"stdout={result.stdout[:100]!r}, stderr={result.stderr[:300]!r}")


def board(root):
    return root / ".blackboard"


def messages(root, channel="general"):
    return sorted((board(root) / "channels" / channel).glob("*.md"))


def publish(root, suffix, body, *, who="writer", channel="general"):
    ident = f"{STAMP}-{who}-{suffix}"
    data = f"---\nfrom: {who}\nat: 2026-10-13T12:00:00.000Z\n---\n\n{body}\n".encode()
    folder = board(root) / "channels" / channel
    folder.mkdir(exist_ok=True)
    staged = board(root) / "tmp" / (ident + ".md")
    staged.write_bytes(data)
    staged.replace(folder / staged.name)
    return ident


def symlink_final_directory(s, part, args):
    label = part.replace("/", "-") + "-" + args[0]
    root = s.root("link-" + label, bare=args[0] == "init")
    target = root / "target"
    target.mkdir()
    sentinel = target / "sentinel"
    sentinel.write_text("keep")
    path = board(root) / part
    if args[0] == "init":
        path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_dir():
        path.rmdir()
    path.symlink_to(target, target_is_directory=True)
    if args[0] == "ack":
        publish(root, "ffff", "mail")
    result = s.call(root, *args)
    require(result.returncode == 1 and result.stdout == b"" and
            result.stderr.strip(), f"{label}: {result.returncode} {result.stderr!r}")
    require(path.is_symlink() and sentinel.read_text() == "keep" and
            sorted(p.name for p in target.iterdir()) == ["sentinel"],
            f"{label}: symlink target was changed")
    if args[0] == "post":
        require(not messages(root), f"{label}: published through a symlink")


def cursor_file_link(s, command):
    root = s.root("cursor-file-link-" + command)
    publish(root, "ffff", "mail")
    alice = board(root) / "cursors/alice"
    bob = board(root) / "cursors/bob"
    alice.mkdir()
    bob.mkdir()
    target = bob / "general"
    target.write_text("bob owns this cursor\n")
    link = alice / "general"
    link.symlink_to("../bob/general")
    result = s.call(root, command, "-f", "alice")
    require(result.returncode == 1 and result.stderr.strip(),
            f"cursor link accepted by {command}: {result.returncode} {result.stderr!r}")
    require(link.is_symlink() and target.read_text() == "bob owns this cursor\n",
            f"{command} changed another agent's cursor")


def permission_error(s, label, path_part, args, prepare=False, mode=0o444):
    root = s.root("permission-" + label)
    if prepare:
        publish(root, "ffff", "mail")
    path = board(root) / path_part
    path.chmod(mode)
    try:
        s.denied(s.call(root, *args))
    finally:
        path.chmod(0o755 if path.is_dir() else 0o644)
    if label == "ack-channel":
        require(not (board(root) / "cursors/reader/general").exists(),
                "ack reported an error after writing a cursor")
    if label in ("write-tmp", "rename-channel"):
        require(not messages(root), "failed post published a message")


def nonblocking_stdin(s):
    root = s.root("nonblocking-stdin")
    sender, receiver = socket.socketpair()
    try:
        for sock in (sender, receiver):
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 4 << 20)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 << 20)
            sock.setblocking(False)
        body = b"X" * (MAX_BODY - 100) + b" " * 100
        offset = 0
        deadline = time.monotonic() + 5
        while offset < len(body):
            try:
                offset += sender.send(body[offset:offset + 65536])
            except BlockingIOError:
                require(time.monotonic() < deadline, "socket could not queue 1 MiB")
                select.select([], [sender], [], 0.1)
        proc = subprocess.run([str(s.binary), "post", "-f", "writer", "-"],
                              cwd=root, env=s.env(root), stdin=receiver,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              timeout=5)
        require(proc.returncode == 1 and proc.stdout == b"" and proc.stderr.strip(),
                f"nonblocking read was treated as EOF: {proc.returncode} {proc.stderr!r}")
        require(not messages(root) and not list((board(root) / "tmp").iterdir()),
                "nonblocking read published an incomplete body")
    finally:
        sender.close()
        receiver.close()


def maximum_post_is_readable(s):
    root = s.root("maximum-post")
    body = b"X" * MAX_BODY
    who = "f" * 64
    reply = "r" * 64
    post = s.ok(s.call(root, "post", "-f", who, "--re", reply, "-", data=body))
    require(ID.fullmatch(post.stdout), f"bad ID: {post.stdout[:100]!r}")
    files = messages(root)
    require(len(files) == 1 and files[0].stat().st_size > MAX_BODY and
            files[0].read_bytes().endswith(body + b"\n"),
            "maximum body was truncated or serialized incorrectly")
    for args in (("log", "--all"), ("unread", "-f", "reader")):
        out = s.ok(s.call(root, *args))
        require(body in out.stdout and post.stdout.strip() in out.stdout,
                f"{args[0]} could not render the successful maximum post")


def exact_cursor_and_migration(s):
    root = s.root("exact-cursor")
    lower = publish(root, "0000", "late-lower")
    higher = publish(root, "ffff", "acknowledged-higher")
    publish(root, "eeee", "own-mail", who="reader")
    cursor = board(root) / "cursors/reader/general"
    cursor.parent.mkdir()
    cursor.write_text(higher)  # Legacy single-ID cursor, without a newline.
    first = s.ok(s.call(root, "unread", "-f", "reader"))
    require(b"late-lower" in first.stdout and b"acknowledged-higher" not in first.stdout
            and b"own-mail" not in first.stdout,
            f"legacy ID behaved as a high-water mark: {first.stdout[:300]!r}")
    seen = s.ok(s.call(root, "unread", "-f", "reader", "--ack"))
    require(b"late-lower" in seen.stdout, "legacy migration omitted the lower ID")
    require(s.ok(s.call(root, "unread", "-f", "reader")).stdout == b"",
            "ack did not retain exact IDs")
    require(cursor.read_bytes() != higher.encode() and lower.encode() in cursor.read_bytes(),
            "legacy cursor did not migrate to exact membership")
    s.ok(s.call(root, "ack", "-f", "reader"))
    require(s.ok(s.call(root, "unread", "-f", "reader")).stdout == b"",
            "repeated ack reopened already-seen mail")


def delayed_lower_id(s):
    root = s.root("delayed-lower-id")
    publish(root, "ffff", "first")
    s.ok(s.call(root, "ack", "-f", "reader"))
    publish(root, "0000", "arrived-later")
    out = s.ok(s.call(root, "unread", "-f", "reader"))
    require(b"arrived-later" in out.stdout and b"first" not in out.stdout,
            f"late lower ID was hidden or old mail replayed: {out.stdout[:300]!r}")
    s.ok(s.call(root, "unread", "-f", "reader", "--ack"))
    require(s.ok(s.call(root, "unread", "-f", "reader")).stdout == b"",
            "late lower ID reappeared after ack")


def opaque_ids_and_reimport(s):
    root = s.root("opaque-ids")
    folder = board(root) / "channels/general"
    ids = ("", "line\nbreak", "a" * 210, "b" * 210)
    data = b"---\nfrom: writer\nat: now\n---\n\nopaque-mail\n"
    for ident in ids:
        (folder / (ident + ".md")).write_bytes(data)
    own = folder / "own.md"
    own.write_bytes(b"---\nfrom: reader\nat: now\n---\n\nown-mail\n")
    first = s.ok(s.call(root, "unread", "-f", "reader"))
    require(first.stdout.count(b"opaque-mail") == len(ids) and
            b"own-mail" not in first.stdout,
            "opaque IDs or own-message filtering failed")
    s.ok(s.call(root, "ack", "-f", "reader"))
    cursor = board(root) / "cursors/reader/general"
    require(cursor.stat().st_size > 256 and cursor.read_bytes().startswith(CURSOR_MAGIC),
            "exact-ID cursor did not encode the larger acknowledged set")
    require(s.ok(s.call(root, "unread", "-f", "reader")).stdout == b"",
            "ack omitted an opaque ID")
    for ident in ("", "line\nbreak"):
        path = folder / (ident + ".md")
        saved = path.read_bytes()
        path.unlink()
        path.write_bytes(saved)
    require(s.ok(s.call(root, "unread", "-f", "reader")).stdout == b"",
            "deleted and reimported acknowledged IDs appeared again")


def long_imported_channel_cursor(s):
    root = s.root("long-imported-channel")
    channel = "x" * 255
    ident = publish(root, "ffff", "long-channel-mail", channel=channel)
    first = s.ok(s.call(root, "unread", "-f", "reader", "-c", channel))
    require(b"long-channel-mail" in first.stdout, "imported channel was unreadable")
    s.ok(s.call(root, "ack", "-f", "reader", "-c", channel))
    cursor = board(root) / "cursors/reader" / channel
    require(cursor.read_bytes() == CURSOR_MAGIC + ident.encode() + b"\x00",
            "long channel cursor did not contain the exact versioned receipt")
    require(s.ok(s.call(root, "unread", "-f", "reader", "-c", channel)).stdout == b"",
            "long channel mail reappeared after ack")
    require(sorted(p.name for p in cursor.parent.iterdir()) == [channel],
            "cursor replacement left a staging file")


def fifo_cursor_rejected(s, command):
    root = s.root("fifo-cursor-" + command)
    publish(root, "ffff", "mail")
    cursor = board(root) / "cursors/reader/general"
    cursor.parent.mkdir()
    os.mkfifo(cursor)
    result = s.call(root, command, "-f", "reader", timeout=2)
    require(result.returncode == 1 and result.stdout == b"" and
            b"malformed cursor file:" in result.stderr and
            b"cursors/reader/general" in result.stderr,
            f"{command} did not promptly reject FIFO cursor: {result.returncode} {result.stderr!r}")
    require(stat.S_ISFIFO(cursor.lstat().st_mode), "FIFO cursor was replaced")


def partial_cursor_write_keeps_previous(s):
    root = s.root("partial-cursor-write")
    publish(root, "0001", "first-mail")
    s.ok(s.call(root, "ack", "-f", "reader"))
    cursor = board(root) / "cursors/reader/general"
    previous = cursor.read_bytes()
    publish(root, "0002", "second-mail")

    def limit_cursor_file():
        signal.signal(signal.SIGXFSZ, signal.SIG_IGN)
        resource.setrlimit(resource.RLIMIT_FSIZE, (len(previous) + 8,) * 2)

    result = subprocess.run([str(s.binary), "ack", "-f", "reader"],
                            cwd=root, env=s.env(root), stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=8,
                            preexec_fn=limit_cursor_file)
    require(result.returncode == 1 and result.stdout == b"" and
            b"WriteFailed" in result.stderr,
            f"partial cursor write did not fail cleanly: {result.returncode} {result.stderr!r}")
    require(cursor.read_bytes() == previous, "partial write changed the prior cursor")
    require(sorted(p.name for p in cursor.parent.iterdir()) == ["general"],
            "partial write left a cursor staging file")
    out = s.ok(s.call(root, "unread", "-f", "reader"))
    require(b"second-mail" in out.stdout and b"first-mail" not in out.stdout,
            "partial write lost new mail or reopened acknowledged mail")


def malformed_cursor(s, content, label):
    root = s.root("malformed-cursor-" + label)
    publish(root, "ffff", "mail")
    cursor = board(root) / "cursors/reader/general"
    cursor.parent.mkdir()
    cursor.write_bytes(content)
    for command in ("unread", "ack"):
        result = s.call(root, command, "-f", "reader")
        require(result.returncode == 1 and result.stdout == b"" and
                b"cursors/reader/general" in result.stderr,
                f"{command} accepted or misreported malformed cursor: {result.stderr[:250]!r}")
        require(cursor.read_bytes() == content, "malformed cursor was overwritten")


def cursor_write_failure_keeps_previous(s):
    root = s.root("cursor-write-failure")
    publish(root, "0001", "first-mail")
    s.ok(s.call(root, "ack", "-f", "reader"))
    cursor = board(root) / "cursors/reader/general"
    previous = cursor.read_bytes()
    publish(root, "0002", "second-mail")
    directory = cursor.parent
    directory.chmod(0o555)
    try:
        s.denied(s.call(root, "ack", "-f", "reader"))
        require(cursor.read_bytes() == previous,
                "failed cursor replacement changed the previous receipt")
    finally:
        directory.chmod(0o755)
    require(not list((board(root) / "tmp").iterdir()),
            "failed cursor replacement left a staging file")
    out = s.ok(s.call(root, "unread", "-f", "reader"))
    require(b"second-mail" in out.stdout and b"first-mail" not in out.stdout,
            "failed cursor write lost new mail or reopened acknowledged mail")


def malformed_message_names_file(s):
    root = s.root("malformed-message")
    name = f"{STAMP}-writer-baad.md"
    (board(root) / "channels/general" / name).write_text(
        "---\nfrom: writer\nat: now\nunknown: value\n---\n\nbody\n")
    for args in (("log", "--all"), ("unread", "-f", "reader", "--ack")):
        result = s.call(root, *args)
        require(result.returncode == 1 and result.stdout == b"" and
                result.stderr.strip() and name.encode() in result.stderr,
                f"{args[0]} omitted the bad filename: {result.stderr[:300]!r}")
    require(not (board(root) / "cursors/reader/general").exists(),
            "malformed unread wrote a cursor")


def failed_delivery_keeps_cursor(s):
    root = s.root("failed-delivery-cursor")
    publish(root, "0001", "alpha-mail", channel="alpha")
    bad = board(root) / "channels/general" / f"{STAMP}-writer-baad.md"
    bad.write_text("---\nfrom: writer\nat: now\nunknown: value\n---\n\nmail\n")
    result = s.call(root, "unread", "-f", "reader", "--ack")
    require(result.returncode == 1 and result.stdout == b"" and result.stderr.strip(),
            f"malformed later channel did not fail cleanly: {result.returncode}")
    require(not (board(root) / "cursors/reader/alpha").exists(),
            "unread acknowledged alpha without delivering it")
    bad.write_text("---\nfrom: writer\nat: now\n---\n\nrepaired-mail\n")
    delivered = s.ok(s.call(root, "unread", "-f", "reader"))
    require(b"alpha-mail" in delivered.stdout and b"repaired-mail" in delivered.stdout,
            "mail was lost after a later channel's malformed message")


def closed_stdout_keeps_cursor(s):
    root = s.root("closed-stdout-cursor")
    publish(root, "0001", "undelivered-mail")
    readonly = root / "readonly"
    readonly.touch()
    fd = os.open(readonly, os.O_RDONLY)
    try:
        result = subprocess.run([str(s.binary), "unread", "-f", "reader", "--ack"],
                                cwd=root, env=s.env(root), stdout=fd,
                                stderr=subprocess.PIPE, timeout=8)
    finally:
        os.close(fd)
    require(result.returncode == 1 and b"WriteFailed" in result.stderr,
            f"closed stdout did not report WriteFailed: {result.returncode} {result.stderr!r}")
    require(not (board(root) / "cursors/reader/general").exists(),
            "unread acknowledged a message that stdout could not deliver")
    require(b"undelivered-mail" in s.ok(s.call(root, "unread", "-f", "reader")).stdout,
            "message was lost after stdout failed")


def concurrent_posts(s):
    root = s.root("concurrent-posts")

    def post(index):
        return s.call(root, "post", "-f", "writer", f"payload-{index:02}")

    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(post, range(12)))
    for result in results:
        s.ok(result)
    ids = [result.stdout.strip() for result in results]
    files = messages(root)
    require(len(files) == len(set(ids)) == 12 and
            {path.stem.encode() for path in files} == set(ids),
            "concurrent writers lost or duplicated an ID")
    contents = [path.read_bytes() for path in files]
    for index in range(12):
        require(sum(f"payload-{index:02}".encode() in data for data in contents) == 1,
                f"payload-{index:02} was lost or torn")
    out = s.ok(s.call(root, "unread", "-f", "reader"))
    require(all(f"payload-{index:02}".encode() in out.stdout for index in range(12)),
            "concurrent posts are not all readable")
    require(not list((board(root) / "tmp").iterdir()), "successful posts left temp files")


def concurrent_cursor_access(s):
    root = s.root("concurrent-cursor")
    first_id = publish(root, "fffe", "A" * (512 << 10))
    proc = subprocess.Popen([str(s.binary), "unread", "-f", "reader", "--ack"],
                            cwd=root, env=s.env(root), stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE)
    try:
        ready, _, _ = select.select([proc.stdout], [], [], 5)
        require(ready, "first unread did not begin delivering its captured scan")
        leading = os.read(proc.stdout.fileno(), 1)
        require(leading and proc.poll() is None,
                "first unread finished before its output could block")
        second_id = publish(root, "ffff", "newer-mail")
        s.ok(s.call(root, "ack", "-f", "reader"))
        require(proc.poll() is None, "first unread was not held while second ack committed")
        remainder, stderr = proc.communicate(timeout=8)
        require(proc.returncode == 0 and stderr == b"" and
                b"newer-mail" not in leading + remainder,
                "first unread did not commit its older captured scan")
    finally:
        if proc.poll() is None:
            proc.terminate()
            proc.communicate(timeout=3)
    require(s.ok(s.call(root, "unread", "-f", "reader")).stdout == b"",
            "older same-agent cursor commit discarded the newer ack")
    cursor = board(root) / "cursors/reader/general"
    require(first_id.encode() in cursor.read_bytes() and
            second_id.encode() in cursor.read_bytes(),
            "concurrent commit failed to merge both captured ID sets")
    first = board(root) / "channels/general" / (first_id + ".md")
    saved = first.read_bytes()
    first.unlink()
    first.write_bytes(saved)
    require(s.ok(s.call(root, "unread", "-f", "reader")).stdout == b"",
            "reimported acknowledged ID appeared again")


def slow_stdin_cancellation(s):
    root = s.root("slow-stdin-cancel")
    proc = subprocess.Popen([str(s.binary), "post", "-f", "writer", "-"],
                            cwd=root, env=s.env(root), stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        proc.stdin.write(b"first half\n")
        proc.stdin.flush()
        time.sleep(0.2)
        require(proc.poll() is None, "post returned before stdin reached EOF")
        require(not messages(root) and not list((board(root) / "tmp").iterdir()),
                "partial stdin became visible")
    finally:
        proc.terminate()
        proc.communicate(timeout=3)
    require(not messages(root) and not list((board(root) / "tmp").iterdir()),
            "cancelled post left a message or temp file")
    s.ok(s.call(root, "post", "-f", "writer", "complete"))
    require(len(messages(root)) == 1, "post could not restart after cancellation")


def watch_delivery(s):
    root = s.root("watch-delivery")
    cursor = board(root) / "cursors/reader/general"
    cursor.parent.mkdir()
    cursor.write_bytes(b"legacy-acknowledged-id")
    proc = subprocess.Popen([str(s.binary), "watch", "-f", "reader", "-t", "3"],
                            cwd=root, env=s.env(root), stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE)
    try:
        time.sleep(0.2)
        require(proc.poll() is None, f"watch exited early: {proc.returncode}")
        ident = f"{STAMP}-writer-1234.md"
        staged = board(root) / "tmp" / ident
        staged.write_text("---\nfrom: writer\nat: now\n---\n\nwatch-mail\n")
        time.sleep(0.2)
        require(proc.poll() is None, "watch observed a staged message")
        staged.replace(board(root) / "channels/general" / ident)
        stdout, stderr = proc.communicate(timeout=4)
        require(proc.returncode == 0 and b"watch-mail" in stdout and stderr == b"",
                f"watch failed delivery: {proc.returncode} {stderr[:200]!r}")
        require(cursor.read_bytes() == b"legacy-acknowledged-id",
                "watch changed or migrated a cursor")
        require(b"watch-mail" in s.ok(s.call(root, "unread", "-f", "reader")).stdout,
                "watch made delivered mail read")
    finally:
        if proc.poll() is None:
            proc.terminate()
            proc.communicate(timeout=3)


def watch_malformed(s):
    root = s.root("watch-malformed")
    name = f"{STAMP}-writer-baad.md"
    (board(root) / "channels/general" / name).write_text(
        "---\nfrom: writer\nat: now\nunknown: value\n---\n\nbody\n")
    result = s.call(root, "watch", "-f", "reader", "-t", "1", timeout=4)
    require(result.returncode == 1 and result.stdout == b"" and
            result.stderr.strip() and name.encode() in result.stderr,
            f"watch omitted the bad filename: {result.stderr[:200]!r}")


def watch_channel_permission(s, mode):
    root = s.root(f"watch-permission-{mode:o}")
    publish(root, "0001", "first-mail")
    s.ok(s.call(root, "ack", "-f", "reader"))
    cursor = board(root) / "cursors/reader/general"
    previous = cursor.read_bytes()
    publish(root, "0002", "second-mail")
    channel = board(root) / "channels/general"
    channel.chmod(mode)
    try:
        s.denied(s.call(root, "watch", "-f", "reader", "-c", "general",
                        "-t", "1", timeout=4))
    finally:
        channel.chmod(0o755)
    require(cursor.read_bytes() == previous,
            f"watch permission failure changed receipt with mode {mode:o}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    parser.add_argument("--watch", action="store_true", help="run native FSEvents checks")
    args = parser.parse_args()
    binary = args.binary.resolve(strict=True)
    base = Path.cwd() / ".build"
    base.mkdir(exist_ok=True)
    run_dir = Path(tempfile.mkdtemp(prefix="regressions-", dir=base))
    suite = Suite(binary, run_dir)
    for part, command in (
        ("channels", ("init",)),
        ("channels/general", ("init",)),
        ("cursors", ("init",)),
        ("tmp", ("init",)),
        ("channels/topic", ("post", "-f", "writer", "-c", "topic", "hello")),
        ("tmp", ("post", "-f", "writer", "hello")),
        ("cursors/reader", ("ack", "-f", "reader")),
    ):
        suite.case(f"final link {part} {command[0]}",
                   lambda part=part, command=command:
                   symlink_final_directory(suite, part, command))
    for command in ("unread", "ack"):
        suite.case(f"cursor file link {command}",
                   lambda command=command: cursor_file_link(suite, command))
    for label, part, command, prepare, mode in (
        ("list-channel", "channels/general", ("unread", "-f", "reader"), True, 0o444),
        ("log-channel", "channels/general", ("log", "--all"), True, 0o444),
        ("ack-channel", "channels/general", ("ack", "-f", "reader"), True, 0o444),
        ("list-channels", "channels", ("channels",), False, 0o444),
        ("write-tmp", "tmp", ("post", "-f", "writer", "hello"), False, 0o555),
        ("rename-channel", "channels/general", ("post", "-f", "writer", "hello"), False, 0o555),
        ("log-message", "channels/general/" + STAMP + "-writer-ffff.md",
         ("log", "--all"), True, 0o000),
        ("unread-message", "channels/general/" + STAMP + "-writer-ffff.md",
         ("unread", "-f", "reader"), True, 0o000),
    ):
        suite.case(f"permission {label}", lambda label=label, part=part,
                   command=command, prepare=prepare, mode=mode:
                   permission_error(suite, label, part, command, prepare, mode))
    for name, fn in (
        ("nonblocking stdin", nonblocking_stdin),
        ("maximum post roundtrip", maximum_post_is_readable),
        ("legacy cursor migration", exact_cursor_and_migration),
        ("delayed lower ID", delayed_lower_id),
        ("opaque IDs and reimport", opaque_ids_and_reimport),
        ("long imported channel cursor", long_imported_channel_cursor),
        ("partial cursor write preserves receipt", partial_cursor_write_keeps_previous),
        ("failed cursor write preserves receipt", cursor_write_failure_keeps_previous),
        ("malformed message filename", malformed_message_names_file),
        ("later malformed preserves prior cursor", failed_delivery_keeps_cursor),
        ("failed stdout preserves cursor", closed_stdout_keeps_cursor),
        ("concurrent posts", concurrent_posts),
        ("concurrent cursor access", concurrent_cursor_access),
        ("slow stdin cancellation", slow_stdin_cancellation),
    ):
        suite.case(name, lambda fn=fn: fn(suite))
    for command in ("unread", "ack"):
        suite.case(f"FIFO cursor {command}",
                   lambda command=command: fifo_cursor_rejected(suite, command))
    suite.case("truncated versioned cursor", lambda: malformed_cursor(
        suite, CURSOR_MAGIC + b"unterminated", "truncated"))
    suite.case("unknown versioned cursor", lambda: malformed_cursor(
        suite, b"\x00bb-cursor-v3\x00name\x00", "unknown-version"))
    if args.watch:
        suite.case("watch delivery without ack", lambda: watch_delivery(suite))
        suite.case("watch malformed filename", lambda: watch_malformed(suite))
        for mode in (0o111, 0o000):
            suite.case(f"watch channel permission {mode:o}",
                       lambda mode=mode: watch_channel_permission(suite, mode))
    print(f"{suite.total - suite.failed}/{suite.total} passed; fixtures: {run_dir}")
    return 1 if suite.failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
