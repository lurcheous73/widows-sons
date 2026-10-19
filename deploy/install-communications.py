#!/usr/bin/env python3
"""Install this project's private communications services on Canada VM20000.

Requires the existing mobile/CMS installation. DNS and public media forwarding
are deliberately a separate deployment step; this configuration advertises the
VM's private address for the authorised development network.
"""
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import secrets
import shutil
import subprocess
import tarfile
import urllib.request

VERSION = '1.13.10'
SHA256 = 'c25a3e45fb922e9a93c6443d10c0ed041ba64342097e38632331736630283165'


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def main():
    marker = dict(line.split('=', 1) for line in Path('/etc/widows-sons-environment').read_text().splitlines() if '=' in line)
    assert marker.get('PROJECT') == 'widows-sons' and marker.get('VMID') == '20000'
    assert run('hostname', capture_output=True).stdout.strip() == 'can-widows-sons-dev'
    root = Path(__file__).resolve().parent.parent
    service = Path('/etc/systemd/system/widows-sons-mobile.service')
    previous = service.read_text()
    assert 'User=widowsapp' in previous and '--port 8009' in previous
    run('/srv/widows-sons/venv/bin/pip', 'install', '-r', str(root / 'backend/requirements.txt'))
    run('runuser', '-u', 'postgres', '--', 'psql', '-v', 'ON_ERROR_STOP=1', '-d', 'widowssons', '-f', str(root / 'backend/community_schema.sql'))
    run('runuser', '-u', 'postgres', '--', 'psql', '-v', 'ON_ERROR_STOP=1', '-d', 'widowssons', '-f', str(root / 'backend/ride_schema.sql'))
    run('runuser', '-u', 'postgres', '--', 'psql', '-v', 'ON_ERROR_STOP=1', '-d', 'widowssons', '-f', str(root / 'backend/clubhouse_schema.sql'))
    grants = '''
GRANT SELECT,INSERT,UPDATE ON conversations,conversation_messages,conversation_reads,member_blocks,message_reports,live_riders,voice_grants TO widowsapp;
GRANT DELETE ON member_blocks,live_riders,voice_grants TO widowsapp;
GRANT USAGE ON SEQUENCE conversation_messages_id_seq TO widowsapp;
GRANT SELECT ON ride_managers,role_grants TO widowsapp;
GRANT SELECT,INSERT,UPDATE ON ride_plans,ride_assignments,ride_participation,ride_incidents,ride_incident_receipts TO widowsapp;
GRANT SELECT,INSERT ON ride_activity TO widowsapp;
GRANT USAGE ON SEQUENCE ride_activity_id_seq TO widowsapp;
GRANT SELECT,INSERT,UPDATE ON clubhouse_sections,clubhouse_memberships,clubhouse_posts,clubhouse_comments,clubhouse_votes,clubhouse_reports TO widowsapp;
GRANT DELETE ON clubhouse_votes TO widowsapp;
GRANT SELECT,INSERT ON clubhouse_activity TO widowsapp;
GRANT USAGE ON SEQUENCE clubhouse_comments_id_seq,clubhouse_activity_id_seq TO widowsapp;
'''
    run('runuser', '-u', 'postgres', '--', 'psql', '-v', 'ON_ERROR_STOP=1', '-d', 'widowssons', input=grants)
    try:
        pwd.getpwnam('widowsvoice')
    except KeyError:
        run('useradd', '--system', '--home-dir', '/var/lib/widowsvoice', '--create-home', '--shell', '/usr/sbin/nologin', 'widowsvoice')
    config = Path('/etc/widows-sons/livekit.json')
    environment = Path('/etc/widows-sons/voice-api.env')
    if config.exists():
        data = json.loads(config.read_text())
        assert data['rtc']['node_ip'] == '10.44.0.200'
        key, secret = next(iter(data['keys'].items()))
    else:
        key, secret = 'ws_' + secrets.token_hex(12), secrets.token_urlsafe(48)
        data = {'port': 7880, 'bind_addresses': ['127.0.0.1'],
                'rtc': {'node_ip': '10.44.0.200', 'use_external_ip': False, 'tcp_port': 17881, 'udp_port': 17882,
                        'enable_loopback_candidate': True},
                'keys': {key: secret}, 'logging': {'level': 'warn'},
                'room': {'empty_timeout': 60, 'max_participants': 50}}
        config.write_text(json.dumps(data, indent=2))
    shutil.chown(config, user='root', group='root')
    config.chmod(0o600)
    environment.write_text(f'WIDOWS_SONS_VOICE_KEY={key}\nWIDOWS_SONS_VOICE_SECRET={secret}\nWIDOWS_SONS_VOICE_INTERNAL=http://127.0.0.1:7880\n')
    environment.chmod(0o600)
    destination = Path('/opt/widows-sons/livekit') / VERSION
    binary = destination / 'livekit-server'
    if not binary.exists():
        destination.mkdir(parents=True, exist_ok=True)
        archive = destination / 'release.tar.gz'
        urllib.request.urlretrieve(f'https://github.com/livekit/livekit/releases/download/v{VERSION}/livekit_{VERSION}_linux_amd64.tar.gz', archive)
        assert hashlib.sha256(archive.read_bytes()).hexdigest() == SHA256, 'LiveKit release checksum mismatch'
        with tarfile.open(archive) as package:
            member = next(item for item in package.getmembers() if item.name in ('livekit-server', './livekit-server'))
            assert member.isfile()
            with package.extractfile(member) as source, binary.open('wb') as target:
                shutil.copyfileobj(source, target)
        binary.chmod(0o755)
        archive.unlink()
    voice_service = f'''[Unit]
Description=Widows Sons ride intercom - Canada VM20000
After=network-online.target
Wants=network-online.target

[Service]
User=widowsvoice
Group=widowsvoice
LoadCredential=livekit.json:/etc/widows-sons/livekit.json
ExecStart={binary} --config %d/livekit.json
Restart=on-failure
RestartSec=3
UMask=0077
LimitNOFILE=65536
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
RestrictSUIDSGID=true
LockPersonality=true

[Install]
WantedBy=multi-user.target
'''
    Path('/etc/systemd/system/widows-sons-intercom.service').write_text(voice_service)
    dropin = Path('/etc/systemd/system/widows-sons-mobile.service.d')
    dropin.mkdir(exist_ok=True)
    (dropin / 'communications.conf').write_text('[Service]\nEnvironmentFile=/etc/widows-sons/voice-api.env\n')
    backup = Path('/etc/widows-sons/mobile-before-communications.service')
    if not backup.exists():
        backup.write_text(previous)
        backup.chmod(0o600)
    service.write_text(re.sub(r'^WorkingDirectory=.*$', 'WorkingDirectory=' + str(root / 'backend'), previous, flags=re.M))
    nginx = Path('/etc/nginx/sites-available/widows-sons')
    original = nginx.read_text()
    replacement = original.replace('client_max_body_size 4k;', 'client_max_body_size 16k;')
    # GPX imports are bounded and validated by the private API (256 KiB raw XML).
    replacement = replacement.replace('client_max_body_size 16k;', 'client_max_body_size 1m;')
    snippet = '''    # BEGIN Widows Sons intercom admission
    location = /_widows_voice_authorize {
        internal;
        proxy_pass http://127.0.0.1:8009/internal/voice-authorize;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_set_header X-Original-URI $request_uri;
        proxy_set_header X-Forwarded-For 127.0.0.1;
        proxy_set_header Authorization $http_authorization;
        access_log off;
        error_log /dev/null crit;
    }
    location ^~ /rtc {
        auth_request /_widows_voice_authorize;
        proxy_pass http://127.0.0.1:7880;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_connect_timeout 5s;
        proxy_read_timeout 75s;
        access_log off;
        error_log /dev/null crit;
    }
    # END Widows Sons intercom admission
'''
    if '# BEGIN Widows Sons intercom admission' in replacement:
        replacement, count = re.subn(r'    # BEGIN Widows Sons intercom admission.*?    # END Widows Sons intercom admission\n', lambda _: snippet, replacement, count=1, flags=re.S)
        assert count == 1
    else:
        replacement = re.sub(r'    # Widows Sons intercom signalling[^\n]*\n    location \^~ /rtc \{.*?\n    \}\n', '', replacement, count=1, flags=re.S)
        assert '    location /api/v1/mobile/' in replacement
        replacement = replacement.replace('    location /api/v1/mobile/', snippet + '    location /api/v1/mobile/', 1)
    nginx_backup = Path('/etc/widows-sons/nginx-before-voice-admission.conf')
    if not nginx_backup.exists():
        nginx_backup.write_text(original)
        nginx_backup.chmod(0o600)
    nginx.write_text(replacement)
    try:
        run('nginx', '-t')
    except Exception:
        nginx.write_text(original)
        service.write_text(previous)
        raise
    run('systemctl', 'daemon-reload')
    run('systemctl', 'enable', '--now', 'widows-sons-intercom.service')
    run('systemctl', 'restart', 'widows-sons-mobile.service')
    run('systemctl', 'reload', 'nginx')
    print('Widows Sons communications installed; voice credentials remain root-only. Private media: TCP 17881 / UDP 17882. Cloudflare unchanged.')


if __name__ == '__main__':
    main()
