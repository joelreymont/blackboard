"""Offline differential E2E benchmark; every board is synthetic and private."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import shutil
import subprocess
import tempfile
import time

BASE = Path(__file__).resolve().parent.parent / '.build'


def fixture(root):
    board = root / '.blackboard'
    for directory in ('channels/general', 'channels/alpha', 'channels/empty', 'cursors', 'tmp'):
        (board / directory).mkdir(parents=True, exist_ok=True)
    for day in range(1, 26):
        who = 'codex' if day % 3 == 0 or day == 25 else 'claude'
        ident = f'202607{day:02}-120000.000-{who}-{day:04x}'
        reply = 're: 20260701-120000.000-claude-0001\n' if day == 3 else ''
        (board / 'channels/general' / (ident + '.md')).write_text(
            f'---\nfrom: {who}\nat: 2026-07-{day:02}T12:00:00.000Z\n{reply}---\n\nmessage {day}\nsecond line\n')
    (board / 'channels/alpha/20260702-130000.000-claude-00ff.md').write_text(
        '---\nfrom: claude\nat: 2026-07-02T13:00:00.000Z\n---\n\nalpha message\n')
    (board / 'channels/general/ignored.txt').write_text('not a message')
    return board


def execute(binary, root, args, input_bytes=None, env_extra=None, subdir=None):
    env = dict(os.environ)
    env.pop('BB_ROOT', None)
    env.pop('BB_AGENT', None)
    env.update(env_extra or {})
    cwd = root / subdir if subdir else root
    cwd.mkdir(parents=True, exist_ok=True)
    p = subprocess.run([str(binary), *args], input=input_bytes, capture_output=True,
                       cwd=cwd, env=env, timeout=15)
    return p.returncode, p.stdout.decode('utf-8', 'surrogateescape'), p.stderr.decode('utf-8', 'surrogateescape')


def cursors(board):
    return {str(p.relative_to(board)): p.read_text()
            for p in sorted((board / 'cursors').rglob('*')) if p.is_file()}


def board_state(board):
    state = {}
    for path in sorted(board.rglob('*')):
        key = str(path.relative_to(board))
        if path.is_symlink():
            state[key] = 'link:' + os.readlink(path)
        elif path.is_dir():
            state[key] = 'dir'
        elif path.is_file():
            state[key] = hashlib.sha256(path.read_bytes()).hexdigest()
    return state


def run_pair(zig, habu):
    BASE.mkdir(parents=True, exist_ok=True)
    run_dir = Path(tempfile.mkdtemp(prefix='parity-', dir=BASE))
    results = []

    def record(name, okay, detail):
        results.append({'case': name, 'pass': okay, 'detail': detail})
        print(('PASS ' if okay else 'FAIL ') + name)

    def case(name, args, *, change=None, env_extra=None, subdir=None, expected_rc=0,
             stderr_exact=True):
        outputs = []
        for language, binary in [('zig', zig), ('habu', habu)]:
            root = run_dir / name / language
            board = fixture(root)
            if change:
                change(board)
            extras = {k: (str(root) if v == '<root>' else v)
                      for k, v in (env_extra or {}).items()}
            out = execute(binary, root, args, env_extra=extras, subdir=subdir)
            outputs.append((*out, cursors(board), board_state(board)))
        z, h = outputs
        okay = z[0] == h[0] == expected_rc and z[1] == h[1] and z[3] == h[3] and z[4] == h[4]
        if stderr_exact:
            okay = okay and z[2] == h[2]
        else:
            okay = okay and bool(z[2]) == bool(h[2])
        record(name, okay, {'zig': z, 'habu': h} if not okay else {'rc': z[0]})

    case('channels', ['channels'])
    case('subcommand-help', ['log', '--help'])
    case('subcommand-short-help', ['post', '-h'])
    case('no-args', [], expected_rc=1)
    case('unknown-command', ['bogus'], expected_rc=1)
    case('top-level-help-upstream-rc', ['--help'], expected_rc=1)

    def special_entries(board):
        (board / 'channels/not-a-channel').write_text('ignore regular channel entry')
        (board / 'channels/linked-channel').symlink_to('general', target_is_directory=True)
        (board / 'channels/general/20261201-120000.000-claude-ffff.md').symlink_to(
            '20260701-120000.000-claude-0001.md')

    case('channels-ignore-nondirs', ['channels'], change=special_entries)
    case('log-ignore-symlink', ['log', '--all'], change=special_entries)
    case('unread-ignore-nondirs', ['unread', '-f', 'codex'], change=special_entries)
    case('ack-ignore-nondirs', ['ack', '-f', 'codex'], change=special_entries)

    def unicode_channel(board):
        (board / 'channels' / ('é' * 200)).mkdir()

    case('unicode-channel-400-bytes', ['channels'], change=unicode_channel)

    def unicode_filename(board):
        (board / 'channels/alpha' / ('é' * 200 + '.md')).write_text(
            '---\nfrom: writer\nat: now\n---\n\nunicode filename\n')

    case('unicode-filename-403-bytes', ['log', '-c', 'alpha', '--all'], change=unicode_filename)

    def prefix_ids(board):
        for name in ('a.md', 'a-.md', '.md'):
            (board / 'channels/empty' / name).write_text(
                '---\nfrom: writer\nat: now\n---\n\n' + name + '\n')

    case('filename-id-order', ['log', '-c', 'empty', '--all'], change=prefix_ids)
    case('filename-id-last', ['log', '-c', 'empty', '-n', '1'], change=prefix_ids)
    case('filename-id-ack', ['ack', '-f', 'reader', '-c', 'empty'], change=prefix_ids)
    case('log-default', ['log'])
    case('log-all', ['log', '--all'])
    case('log-last3', ['log', '-n', '3'])
    case('log-zero', ['log', '-n', '0'])
    case('log-large-n', ['log', '-n', '100'])
    case('log-since', ['log', '--since', '2026-07-20'])
    case('log-since-with-n', ['log', '--since', '2026-07-20', '-n', '2'])
    case('log-md', ['log', '--md', '-n', '4'])
    case('log-empty', ['log', '-c', 'empty'])
    case('log-empty-md', ['log', '-c', 'empty', '--md'])
    case('log-other-channel', ['log', '-c', 'alpha'])
    case('log-invalid-filter-is-missing', ['log', '-c', 'Upper'], expected_rc=1)
    case('unread-invalid-filter-is-empty', ['unread', '-f', 'codex', '-c', '../general'])
    case('ack-invalid-filter-is-empty', ['ack', '-f', 'codex', '-c', '../general'])
    case('flag-value-last-wins', ['log', '-n', '1', '-n', '3'])
    case('flag-n-plus', ['log', '-n', '+2'])
    case('flag-n-negative-zero', ['log', '-n', '-0'])
    case('flag-n-underscores', ['log', '-n', '1__2'])
    case('flag-n-uint64-max', ['log', '-n', '18446744073709551615'])
    case('flag-t-u32-max', ['channels', '-t', '4294967295'])
    case('flag-t-underscores', ['channels', '-t', '4__2'])
    case('root-empty-env', ['channels'], env_extra={'BB_ROOT': ''})

    def missing_empty_root():
        outputs = []
        for language, binary in [('zig', zig), ('habu', habu)]:
            root = run_dir / 'missing-empty-root' / language
            root.mkdir(parents=True)
            outputs.append(execute(binary, root, ['channels'], env_extra={'BB_ROOT': ''}))
        expected = (1, '', 'bb: no .blackboard/ at .blackboard (run `bb init`)\n')
        record('missing-empty-root', outputs == [expected] * 2, {'outputs': outputs})

    missing_empty_root()
    case('identity-empty-env', ['unread'], env_extra={'BB_AGENT': ''}, expected_rc=1)
    case('missing-root-env', ['channels'], env_extra={'BB_ROOT': 'nowhere'}, expected_rc=1)
    case('long-invalid-identity', ['unread', '-f', 'X' * 5000], expected_rc=1)

    def root_file_case():
        outputs = []
        for language, binary in [('zig', zig), ('habu', habu)]:
            root = run_dir / 'root-is-file' / language
            root.mkdir(parents=True)
            (root / '.blackboard').write_text('file')
            outputs.append(execute(binary, root, ['channels'], env_extra={'BB_ROOT': str(root)}))
        record('root-is-file', outputs[0] == outputs[1] and outputs[0][0] == 1,
               {} if outputs[0] == outputs[1] else {'zig': outputs[0], 'habu': outputs[1]})

    root_file_case()

    def init_root_file():
        outputs = []
        for language, binary in [('zig', zig), ('habu', habu)]:
            root = run_dir / 'init-root-file' / language
            root.mkdir(parents=True)
            (root / '.blackboard').write_text('file')
            outputs.append(execute(binary, root, ['init']))
        record('init-root-file', outputs == [(1, '', 'error: NotDir\n')] * 2,
               {'outputs': outputs})

    init_root_file()
    case('root-upward', ['log', '-n', '1'], subdir='nested/deep')
    case('root-env', ['channels'], env_extra={'BB_ROOT': '<root>'}, subdir='nested')

    def inaccessible_nearest_root():
        outputs = []
        for language, binary in [('zig', zig), ('habu', habu)]:
            root = run_dir / 'nearest-root-unreadable' / language
            fixture(root)
            nested = root / 'nested'
            nested.mkdir()
            nearest = nested / '.blackboard'
            nearest.mkdir()
            nearest.chmod(0)
            try:
                outputs.append(execute(binary, root, ['channels'], subdir='nested'))
            finally:
                nearest.chmod(0o700)
        record('nearest-root-unreadable',
               outputs == [(1, '', 'error: AccessDenied\n')] * 2, {'outputs': outputs})

    inaccessible_nearest_root()

    def nearest_search_only_root():
        outputs = []
        for language, binary in [('zig', zig), ('habu', habu)]:
            root = run_dir / 'nearest-root-mode0111' / language
            fixture(root)
            nested = root / 'nested'
            nearest = nested / '.blackboard'
            (nearest / 'channels/local').mkdir(parents=True)
            nearest.chmod(0o111)
            try:
                outputs.append(execute(binary, root, ['channels'], subdir='nested'))
            finally:
                nearest.chmod(0o700)
        record('nearest-root-mode0111',
               outputs == [(1, '', 'error: AccessDenied\n')] * 2,
               {'outputs': outputs})

    nearest_search_only_root()

    def root_symlink_loop():
        outputs = []
        for language, binary in [('zig', zig), ('habu', habu)]:
            root = run_dir / 'root-symlink-loop' / language
            root.mkdir(parents=True)
            (root / '.blackboard').symlink_to('.blackboard', target_is_directory=True)
            outputs.append(execute(binary, root, ['channels']))
        record('root-symlink-loop',
               outputs == [(1, '', 'error: SymLinkLoop\n')] * 2,
               {'outputs': outputs})

    root_symlink_loop()

    def channels_symlink_loop(board):
        shutil.rmtree(board / 'channels')
        (board / 'channels').symlink_to('channels', target_is_directory=True)

    case('channels-symlink-loop', ['channels'], change=channels_symlink_loop,
         expected_rc=1)

    def cursor_symlink_loop(board):
        directory = board / 'cursors/reader'
        directory.mkdir()
        (directory / 'general').symlink_to('general')

    case('read-cursor-symlink-loop', ['unread', '-f', 'reader', '-c', 'general'],
         change=cursor_symlink_loop, expected_rc=1)
    case('write-cursor-symlink-loop', ['ack', '-f', 'reader', '-c', 'general'],
         change=cursor_symlink_loop, expected_rc=1)

    def discovery_length_boundary():
        outputs = []
        for language, binary in [('zig', zig), ('habu', habu)]:
            root = run_dir / 'discovery-length-boundary' / language
            fixture(root)
            path = root
            while 1016 - len(str(path)) > 101:
                path /= 'd' * 100
            remaining = 1016 - len(str(path)) - 1
            if remaining == 0:
                path = path.parent / (path.name[:-1])
                remaining = 1
            path /= 'd' * remaining
            path.mkdir(parents=True)
            outputs.append(execute(binary, root, ['channels'], subdir=path.relative_to(root)))
        record('discovery-length-boundary',
               outputs == [(1, '', 'error: NameTooLong\n')] * 2, {'outputs': outputs})

    discovery_length_boundary()

    deep = '/'.join(['d' * 96] * 9)
    case('deep-cwd-log', ['log', '-n', '1'], subdir=deep)
    case('deep-cwd-channels', ['channels'], subdir=deep)
    case('unread-all', ['unread', '-f', 'codex'])
    case('unread-filter', ['unread', '-f', 'codex', '-c', 'alpha'])
    case('identity-env', ['unread', '-c', 'alpha'], env_extra={'BB_AGENT': 'codex'})
    case('unread-ack', ['unread', '-f', 'codex', '--ack'])
    case('unread-ack-filter', ['unread', '-f', 'codex', '-c', 'general', '--ack'])
    case('ack', ['ack', '-f', 'codex'])
    case('ack-filter', ['ack', '-f', 'codex', '-c', 'general'])

    def missing_channels(board):
        for path in (board / 'channels').rglob('*'):
            if path.is_file() or path.is_symlink():
                path.unlink()
        for path in sorted((board / 'channels').rglob('*'), reverse=True):
            if path.is_dir():
                path.rmdir()
        (board / 'channels').rmdir()

    case('channels-missing', ['channels'], change=missing_channels, expected_rc=1)
    case('log-missing-channels', ['log'], change=missing_channels, expected_rc=1)

    def channels_file(board):
        missing_channels(board)
        (board / 'channels').write_text('file')

    case('channels-file', ['channels'], change=channels_file, expected_rc=1)
    case('channel-file', ['log', '-c', 'not-a-dir'],
         change=lambda b: (b / 'channels/not-a-dir').write_text('file'), expected_rc=1)
    case('post-channel-file', ['post', '-f', 'writer', '-c', 'not-a-dir', 'hello'],
         change=lambda b: (b / 'channels/not-a-dir').write_text('file'), expected_rc=1)

    def cursors_file(board):
        (board / 'cursors').rmdir()
        (board / 'cursors').write_text('file')

    case('cursors-file', ['unread', '-f', 'reader'], change=cursors_file, expected_rc=1)

    def cursor_directory(board):
        (board / 'cursors/reader/general').mkdir(parents=True)

    case('cursor-directory', ['unread', '-f', 'reader', '-c', 'general'],
         change=cursor_directory, expected_rc=1)
    case('ack-cursor-directory', ['ack', '-f', 'reader', '-c', 'general'],
         change=cursor_directory, expected_rc=1)

    def with_cursor(board):
        p = board / 'cursors/codex/general'
        p.parent.mkdir(parents=True)
        p.write_text('20260720-120000.000-claude-0014\n')

    case('unread-existing-cursor', ['unread', '-f', 'codex', '-c', 'general'], change=with_cursor)

    def unreadable_cursor():
        outputs = []
        for language, binary in [('zig', zig), ('habu', habu)]:
            root = run_dir / 'unreadable-cursor' / language
            board = fixture(root)
            cursor = board / 'cursors/reader/general'
            cursor.parent.mkdir()
            cursor.write_text('a\n')
            cursor.chmod(0)
            try:
                outputs.append(execute(binary, root, ['unread', '-f', 'reader', '-c', 'general']))
            finally:
                cursor.chmod(0o600)
        record('unreadable-cursor',
               outputs == [(1, '', 'error: AccessDenied\n')] * 2, {'outputs': outputs})

    unreadable_cursor()
    for name, args in [
        ('bad-identity', ['unread', '-f', 'Upper']),
        ('missing-identity', ['unread']),
        ('bad-channel', ['post', '-f', 'codex', '-c', '../bad', 'text']),
        ('empty-post', ['post', '-f', 'codex', ' \t\n']),
        ('missing-post-text', ['post', '-f', 'codex']),
        ('bad-date', ['log', '--since', '2026-99-03']),
        ('bad-number', ['log', '-n', 'abc']),
        ('bad-number-negative', ['log', '-n', '-1']),
        ('bad-number-overflow', ['log', '-n', '18446744073709551616']),
        ('bad-number-underscore-edge', ['log', '-n', '_1']),
        ('bad-t-overflow', ['channels', '-t', '4294967296']),
        ('bad-t-negative', ['channels', '-t', '-1']),
        ('bad-re', ['post', '-f', 'codex', '--re', 'Upper', 'body']),
        ('bad-re-before-missing-body', ['post', '-f', 'codex', '--re', 'Upper']),
        ('missing-flag-value', ['log', '-n']),
        ('unknown-flag', ['log', '--bogus']),
        ('extra-positional', ['post', '-f', 'codex', 'one', 'two']),
        ('missing-channel', ['log', '-c', 'absent']),
    ]:
        case(name, args, expected_rc=1)

    for name, data in [
        ('bad-frontmatter-key', '---\nfrom: claude\nat: now\nbogus: value\n---\n\nbody\n'),
        ('missing-frontmatter-at', '---\nfrom: claude\n---\n\nbody\n'),
        ('bad-frontmatter-line', '---\nfrom claude\nat: now\n---\n\nbody\n'),
    ]:
        def corrupt(board, data=data):
            (board / 'channels/alpha/20260702-130000.000-claude-00ff.md').write_text(data)
        case(name, ['log', '-c', 'alpha'], change=corrupt, expected_rc=1)

    def body_separators(board):
        (board / 'channels/alpha/20260702-130000.000-claude-00ff.md').write_text(
            '---\nfrom: claude\nat: now\n---\n\n---\nfake: fm\n---\n')
    case('body-frontmatter-like', ['log', '-c', 'alpha', '--md'], change=body_separators)

    def late_bad(board):
        (board / 'channels/general/20260725-120000.000-codex-0019.md').write_text('broken\n')

    case('log-late-malformed-no-stdout', ['log', '--all'], change=late_bad, expected_rc=1)
    case('unread-late-malformed-no-stdout', ['unread', '-f', 'reader', '--ack'], change=late_bad, expected_rc=1)

    def oversized_message(board):
        (board / 'channels/alpha/20260702-130000.000-claude-00ff.md').write_bytes(b'x' * (1 << 20) + b'x')

    case('complete-message-limit', ['log', '-c', 'alpha'], change=oversized_message, expected_rc=1)

    def oversized_cursor(board):
        path = board / 'cursors/reader/general'
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b'x' * 257)

    case('cursor-limit', ['unread', '-f', 'reader', '-c', 'general'], change=oversized_cursor, expected_rc=1)

    def newline_filename(board):
        path = board / 'channels/alpha/20260703\nnext.md'
        path.write_text('---\nfrom: claude\nat: now\n---\n\nnewline filename\n')

    case('newline-filename', ['log', '-c', 'alpha', '--all'], change=newline_filename)

    def long_filename(board):
        path = board / 'channels/alpha' / ('x' * 210 + '.md')
        path.write_text('---\nfrom: claude\nat: now\n---\n\nlong filename\n')

    case('long-filename-id', ['log', '-c', 'alpha', '--all'], change=long_filename)

    def newline_channel(board):
        (board / 'channels/line\nbreak').mkdir()

    case('newline-channel', ['channels'], change=newline_channel)

    def large_listing(board):
        directory = board / 'channels/alpha'
        data = '---\nfrom: claude\nat: now\n---\n\nlarge listing\n'
        for i in range(4300):
            (directory / (f'f{i:04}' + 'a' * 242 + '.md')).write_text(data)

    case('listing-over-one-megabyte', ['log', '-c', 'alpha', '-n', '1'], change=large_listing)

    for language, binary in [('zig', zig), ('habu', habu)]:
        root = run_dir / 'roundtrip' / language
        root.mkdir(parents=True)
        init = execute(binary, root, ['init'])
        expected = f'initialized {root}/.blackboard\n'
        record(language + '-init', init == (0, expected, ''), {'result': init})
        record(language + '-init-idempotent', execute(binary, root, ['init']) == init, {})
        for label, args, stdin, body, reply in [
            ('argument', ['post', '-f', 'codex', '  hello\nworld \t'], None, 'hello\nworld', None),
            ('stdin-reply', ['post', '-f', 'codex', '-c', 'topic', '--re', 'prior-id', '-'],
             b'\nstdin body\n\n', 'stdin body', 'prior-id'),
        ]:
            out = execute(binary, root, args, stdin)
            ident = out[1].strip()
            valid = out[0] == 0 and out[2] == '' and bool(re.fullmatch(
                r'\d{8}-\d{6}\.\d{3}-codex-[0-9a-f]{4}', ident))
            chan = 'topic' if label == 'stdin-reply' else 'general'
            path = root / '.blackboard/channels' / chan / (ident + '.md')
            content = path.read_text() if path.is_file() else ''
            at = re.search(r'^at: (.+)$', content, re.M)
            if at:
                try:
                    instant = datetime.datetime.fromisoformat(at[1].replace('Z', '+00:00'))
                    valid = valid and ident.startswith(instant.strftime('%Y%m%d-%H%M%S.') + f'{instant.microsecond // 1000:03}')
                except ValueError:
                    valid = False
            else:
                valid = False
            expected_re = f're: {reply}\n' if reply else ''
            valid = valid and content == f'---\nfrom: codex\nat: {at[1] if at else ""}\n{expected_re}---\n\n{body}\n'
            valid = valid and not list((root / '.blackboard/tmp').iterdir())
            record(language + '-post-' + label, valid, {'result': out, 'content': content})
        unread = execute(binary, root, ['unread', '-f', 'claude', '--ack'])
        again = execute(binary, root, ['unread', '-f', 'claude'])
        own = execute(binary, root, ['unread', '-f', 'codex', '--ack'])
        record(language + '-roundtrip-ack', unread[0] == 0 and 'hello\nworld' in unread[1]
               and 'stdin body' in unread[1] and again == (0, '', '') and own == (0, '', ''), {})

    for label in ('deep-cwd-post', 'missing-tmp-post', 'tmp-file-post'):
        outputs = []
        for language, binary in [('zig', zig), ('habu', habu)]:
            root = run_dir / label / language
            board = fixture(root)
            subdir = deep if label == 'deep-cwd-post' else None
            if label != 'deep-cwd-post':
                (board / 'tmp').rmdir()
                if label == 'tmp-file-post':
                    (board / 'tmp').write_text('file')
            result = execute(binary, root, ['post', '-f', 'writer', 'new body'], subdir=subdir)
            ident = result[1].strip()
            target = board / 'channels/general' / (ident + '.md')
            if label == 'tmp-file-post':
                okay = result == (1, '', 'error: NotDir\n')
            else:
                okay = (result[0] == 0 and result[2] == '' and
                        re.fullmatch(r'\d{8}-\d{6}\.\d{3}-writer-[0-9a-f]{4}', ident) and
                        target.is_file() and 'new body\n' in target.read_text() and
                        (board / 'tmp').is_dir() and not list((board / 'tmp').iterdir()))
            outputs.append((bool(okay), result))
        record(label, all(v[0] for v in outputs), {'outputs': outputs})

    outputs = []
    for language, binary in [('zig', zig), ('habu', habu)]:
        root = run_dir / 'readonly-stdout' / language
        fixture(root)
        readonly = root / 'readonly'
        readonly.touch()
        fd = os.open(readonly, os.O_RDONLY)
        try:
            p = subprocess.run([str(binary), 'channels'], cwd=root, stdout=fd,
                               stderr=subprocess.PIPE, timeout=15)
        finally:
            os.close(fd)
        outputs.append((p.returncode, p.stderr.decode()))
    record('readonly-stdout', outputs == [(1, 'error: WriteFailed\n')] * 2,
           {'outputs': outputs})

    def watch_case(name, *, chan='general', immediate=False, timeout=False,
                   filtered=False, ack=False, malformed=False, stage_first=False):
        outputs = []
        for language, binary in [('zig', zig), ('habu', habu)]:
            root = run_dir / name / language
            root.mkdir(parents=True)
            init = execute(binary, root, ['init'])
            assert init[0] == 0, init
            board = root / '.blackboard'

            def publish(stage_only=False):
                directory = board / 'channels' / chan
                directory.mkdir(parents=True, exist_ok=True)
                ident = '20261012-120000.000-writer-1234.md'
                data = ('broken\n' if malformed else
                        '---\nfrom: writer\nat: 2026-10-12T12:00:00.000Z\n---\n\nwatch message\n')
                staged = board / 'tmp' / ident
                staged.write_text(data)
                target = directory / ident
                if stage_only:
                    return staged, target
                os.replace(staged, target)

            if immediate:
                publish()
            args = [str(binary), 'watch', '-f', 'reader', '-t', '1']
            if filtered:
                args += ['-c', chan]
            if ack:
                args += ['--ack']
            start = time.monotonic()
            proc = subprocess.Popen(args, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            blocked = True
            if not immediate and not timeout:
                time.sleep(.15)
                blocked = proc.poll() is None
                if blocked:
                    if stage_first:
                        staged, target = publish(stage_only=True)
                        time.sleep(.15)
                        blocked = blocked and proc.poll() is None
                        os.replace(staged, target)
                    else:
                        publish()
            out, err = proc.communicate(timeout=3)
            elapsed = time.monotonic() - start
            outputs.append((proc.returncode, out, err, board_state(board), blocked, elapsed))
        z, h = outputs
        expected_rc = 2 if timeout else 1 if malformed else 0
        okay = (z[:5] == h[:5] and z[0] == expected_rc and
                (not timeout or z[5] >= .8 and h[5] >= .8) and
                (immediate or timeout or z[4] and h[4]))
        record(name, okay, {'zig': z, 'habu': h} if not okay else
               {'rc': expected_rc, 'zig_elapsed': round(z[5], 2), 'habu_elapsed': round(h[5], 2)})

    watch_case('watch-timeout', timeout=True)
    watch_case('watch-existing-immediate', immediate=True)
    watch_case('watch-existing-event')
    watch_case('watch-new-channel-event', chan='topic')
    watch_case('watch-filtered-new-channel-event', chan='topic', filtered=True)
    watch_case('watch-ack-flag-ignored', immediate=True, ack=True)
    watch_case('watch-malformed-existing', immediate=True, malformed=True)
    watch_case('watch-atomic-publish', stage_first=True)

    def moved_watched_channel(outside_board):
        label = 'watch-moved-channel-outside-board' if outside_board else 'watch-moved-channel-inside-board'
        outputs = []
        for language, binary in [('zig', zig), ('habu', habu)]:
            root = run_dir / label / language
            root.mkdir(parents=True)
            assert execute(binary, root, ['init'])[0] == 0
            board = root / '.blackboard'
            alpha = board / 'channels/alpha'
            alpha.mkdir()
            (alpha / 'a.md').write_text('---\nfrom: writer\nat: now\n---\n\nalpha message\n')
            cursor = board / 'cursors/reader/alpha'
            cursor.parent.mkdir()
            cursor.write_text('a\n')
            proc = subprocess.Popen([str(binary), 'watch', '-f', 'reader', '-t', '2'],
                                    cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            time.sleep(.15)
            waiting = proc.poll() is None
            retired = (root if outside_board else board / 'tmp') / 'retired'
            (board / 'channels/general').rename(retired)
            time.sleep(.2)
            settled = proc.poll() is None
            cursor.unlink()
            time.sleep(.15)
            cursor_reset_ignored = proc.poll() is None
            (retired / 'trigger').write_text('event')
            out, err = proc.communicate(timeout=4)
            outputs.append((waiting, settled, cursor_reset_ignored,
                            proc.returncode, out, err))
        record(label, all(
            waiting and settled and ignored and rc == 0 and
            b'alpha message' in out and err == b''
            for waiting, settled, ignored, rc, out, err in outputs),
            {'outputs': [str(x) for x in outputs]})

    moved_watched_channel(False)
    moved_watched_channel(True)

    def unrelated_events_timeout():
        outputs = []
        for language, binary in [('zig', zig), ('habu', habu)]:
            root = run_dir / 'watch-unrelated-events-timeout' / language
            root.mkdir(parents=True)
            assert execute(binary, root, ['init'])[0] == 0
            start = time.monotonic()
            proc = subprocess.Popen([str(binary), 'watch', '-f', 'reader', '-t', '1'],
                                    cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            time.sleep(.15)
            waiting = proc.poll() is None
            for i in range(5):
                (root / '.blackboard/tmp' / f'irrelevant-{i}').write_text('event')
                time.sleep(.12)
            out, err = proc.communicate(timeout=3)
            outputs.append((waiting, proc.returncode, out, err,
                            time.monotonic() - start))
        record('watch-unrelated-events-timeout', all(
            waiting and rc == 2 and out == b'' and err == b'' and .8 <= elapsed < 1.5
            for waiting, rc, out, err, elapsed in outputs),
            {'outputs': [str(x) for x in outputs]})

    unrelated_events_timeout()

    for label in ('cursor-reset', 'existing-message-edit'):
        outputs = []
        for language, binary in [('zig', zig), ('habu', habu)]:
            root = run_dir / ('watch-ignore-' + label) / language
            root.mkdir(parents=True)
            assert execute(binary, root, ['init'])[0] == 0
            board = root / '.blackboard'
            message = board / 'channels/general/a.md'
            if label == 'cursor-reset':
                message.write_text('---\nfrom: writer\nat: now\n---\n\nmessage\n')
                cursor = board / 'cursors/reader/general'
                cursor.parent.mkdir()
                cursor.write_text(message.stem + '\n')
            else:
                message.write_text('---\nfrom: reader\nat: now\n---\n\nmessage\n')
            proc = subprocess.Popen([str(binary), 'watch', '-f', 'reader', '-c', 'general', '-t', '1'],
                                    cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            time.sleep(.15)
            waiting = proc.poll() is None
            if label == 'cursor-reset':
                cursor.unlink()
            else:
                message.write_text(message.read_text().replace('from: reader', 'from: writer'))
            out, err = proc.communicate(timeout=3)
            outputs.append((waiting, proc.returncode, out, err))
        record('watch-ignore-' + label,
               outputs == [(True, 2, b'', b'')] * 2, {'outputs': [str(x) for x in outputs]})

    for label in ('hardlink-new-name', 'delete-recreate', 'rename-back'):
        outputs = []
        for language, binary in [('zig', zig), ('habu', habu)]:
            root = run_dir / ('watch-' + label) / language
            root.mkdir(parents=True)
            assert execute(binary, root, ['init'])[0] == 0
            board = root / '.blackboard'
            original = board / 'channels/general/a.md'
            old_from = 'writer' if label == 'hardlink-new-name' else 'reader'
            original.write_text(f'---\nfrom: {old_from}\nat: now\n---\n\nmessage\n')
            if label == 'hardlink-new-name':
                cursor = board / 'cursors/reader/general'
                cursor.parent.mkdir()
                cursor.write_text('a\n')
            proc = subprocess.Popen([str(binary), 'watch', '-f', 'reader', '-c', 'general', '-t', '2'],
                                    cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            time.sleep(.15)
            waiting = proc.poll() is None
            if label == 'hardlink-new-name':
                os.link(original, original.with_name('z.md'))
            elif label == 'delete-recreate':
                original.unlink()
                original.write_text('---\nfrom: writer\nat: now\n---\n\nmessage\n')
            else:
                staged = board / 'tmp/a.md'
                original.rename(staged)
                staged.write_text('---\nfrom: writer\nat: now\n---\n\nmessage\n')
                staged.rename(original)
            out, err = proc.communicate(timeout=4)
            outputs.append((waiting, proc.returncode, out, err))
        record('watch-' + label, all(
            waiting and rc == 0 and b'writer' in out and err == b''
            for waiting, rc, out, err in outputs),
            {'outputs': [str(x) for x in outputs]})

    outputs = []
    for language, binary in [('zig', zig), ('habu', habu)]:
        root = run_dir / 'watch-replacement-channel' / language
        root.mkdir(parents=True)
        assert execute(binary, root, ['init'])[0] == 0
        board = root / '.blackboard'
        proc = subprocess.Popen([str(binary), 'watch', '-f', 'reader', '-c', 'general', '-t', '2'],
                                cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        time.sleep(.15)
        waiting = proc.poll() is None
        old = board / 'channels/general'
        old.rename(board / 'channels/retired')
        old.mkdir()
        time.sleep(.5)
        settled = proc.poll() is None
        staged = board / 'tmp/z.md'
        staged.write_text('---\nfrom: writer\nat: now\n---\n\nreplacement message\n')
        staged.rename(old / 'z.md')
        out, err = proc.communicate(timeout=4)
        outputs.append((waiting, settled, proc.returncode, out, err))
    record('watch-replacement-channel', all(
        waiting and settled and rc == 2 and out == b'' and err == b''
        for waiting, settled, rc, out, err in outputs),
        {'outputs': [str(x) for x in outputs]})

    outputs = []
    for language, binary in [('zig', zig), ('habu', habu)]:
        root = run_dir / 'watch-concurrent-post' / language
        root.mkdir(parents=True)
        assert execute(binary, root, ['init'])[0] == 0
        proc = subprocess.Popen([str(binary), 'watch', '-f', 'reader', '-t', '2'],
                                cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        time.sleep(.15)
        waiting = proc.poll() is None
        post = execute(binary, root, ['post', '-f', 'writer', 'concurrent body'])
        out, err = proc.communicate(timeout=4)
        outputs.append((waiting, post[0] == 0, proc.returncode, out, err))
    record('watch-concurrent-post', all(
        waiting and posted and rc == 0 and b'concurrent body' in out and err == b''
        for waiting, posted, rc, out, err in outputs), {'outputs': [str(x) for x in outputs]})

    outputs = []
    for language, binary in [('zig', zig), ('habu', habu)]:
        root = run_dir / 'watch-root-replaced' / language
        root.mkdir(parents=True)
        assert execute(binary, root, ['init'])[0] == 0
        original = root / '.blackboard'
        proc = subprocess.Popen([str(binary), 'watch', '-f', 'reader', '-t', '2'],
                                cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        time.sleep(.15)
        waiting = proc.poll() is None
        moved_parent = run_dir / 'watch-root-replaced' / (language + '-moved-parent')
        moved_parent.mkdir()
        old = moved_parent / '.old'
        original.rename(old)
        (original / 'channels/general').mkdir(parents=True)
        (original / 'cursors').mkdir()
        (original / 'tmp').mkdir()
        (original / 'channels/general/b.md').write_text(
            '---\nfrom: writer\nat: now\n---\n\nNEW ROOT\n')
        (old / 'channels/general/a.md').write_text(
            '---\nfrom: writer\nat: now\n---\n\nORIGINAL ROOT\n')
        out, err = proc.communicate(timeout=4)
        outputs.append((waiting, proc.returncode, out, err))
    record('watch-root-replaced', all(
        waiting and rc == 0 and b'ORIGINAL ROOT' in out and b'NEW ROOT' not in out and err == b''
        for waiting, rc, out, err in outputs), {'outputs': [str(x) for x in outputs]})

    outputs = []
    for language, binary in [('zig', zig), ('habu', habu)]:
        root = run_dir / 'watch-many-channels' / language
        root.mkdir(parents=True)
        assert execute(binary, root, ['init'])[0] == 0
        for i in range(70):
            (root / '.blackboard/channels' / f'channel-{i:03}').mkdir()

        def low_fd_limit():
            resource.setrlimit(resource.RLIMIT_NOFILE, (64, 64))

        p = subprocess.run([str(binary), 'watch', '-f', 'reader', '-t', '1'], cwd=root,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           preexec_fn=low_fd_limit, timeout=4)
        outputs.append((p.returncode, p.stdout, p.stderr))
    record('watch-many-channels-low-fd-limit',
           outputs == [(2, b'', b'')] * 2,
           {'outputs': [str(x) for x in outputs]})

    result = {'run_dir': str(run_dir), 'passed': sum(r['pass'] for r in results),
              'total': len(results), 'results': results}
    (run_dir / 'results.json').write_text(json.dumps(result, indent=2,
                                                      default=lambda o: repr(o)))
    print(json.dumps({'passed': result['passed'], 'total': result['total'], 'run_dir': str(run_dir)}))
    return all(r['pass'] for r in results)


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('zig', type=Path)
    p.add_argument('habu', type=Path)
    a = p.parse_args()
    raise SystemExit(0 if run_pair(a.zig.resolve(), a.habu.resolve()) else 1)
