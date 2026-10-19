#!/usr/bin/env python3
"""Add ordinary clubhouse sections to the dedicated private mobile service.

No CMS, NPM, DNS, media routing or existing welfare-table permissions change.
Run as root from the immutable release directory on Canada VM20000.
"""
from pathlib import Path
import re
import subprocess


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def main():
    assert dict(line.split('=', 1) for line in Path('/etc/widows-sons-environment').read_text().splitlines() if '=' in line).get('VMID') == '20000'
    assert run('hostname', capture_output=True).stdout.strip() == 'can-widows-sons-dev'
    root = Path(__file__).resolve().parent.parent
    assert root.parent == Path('/srv/widows-sons/releases') and (root / 'backend/clubhouse.py').exists()
    service = Path('/etc/systemd/system/widows-sons-mobile.service')
    original = service.read_text()
    assert 'User=widowsapp' in original and '--port 8009' in original
    run('runuser', '-u', 'postgres', '--', 'psql', '-v', 'ON_ERROR_STOP=1', '-d', 'widowssons', '-f', str(root / 'backend/clubhouse_schema.sql'))
    run('runuser', '-u', 'postgres', '--', 'psql', '-v', 'ON_ERROR_STOP=1', '-d', 'widowssons', input='''
GRANT SELECT,INSERT,UPDATE ON clubhouse_sections,clubhouse_memberships,clubhouse_posts,clubhouse_comments,clubhouse_votes,clubhouse_reports TO widowsapp;
GRANT DELETE ON clubhouse_votes TO widowsapp;
GRANT SELECT,INSERT ON clubhouse_activity TO widowsapp;
GRANT USAGE ON SEQUENCE clubhouse_comments_id_seq,clubhouse_activity_id_seq TO widowsapp;
''')
    backup = Path('/etc/widows-sons/mobile-before-sections.service')
    if not backup.exists():
        backup.write_text(original)
        backup.chmod(0o600)
    service.write_text(re.sub(r'^WorkingDirectory=.*$', 'WorkingDirectory=' + str(root / 'backend'), original, flags=re.M))
    run('systemctl', 'daemon-reload')
    run('systemctl', 'restart', 'widows-sons-mobile.service')
    run('systemctl', 'is-active', '--quiet', 'widows-sons-mobile.service')
    print('Ordinary sections installed. No member permissions were delegated; welfare tables remain ungranted.')


if __name__ == '__main__':
    main()
