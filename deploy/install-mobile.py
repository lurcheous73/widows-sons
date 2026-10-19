#!/usr/bin/env python3
"""Install/update the isolated mobile API on the existing Canada VM20000.

Run as root from a deployed source release. Does not install WordPress, issue
invitations, seed members, alter NPM, or change public DNS.
"""
import pathlib
import pwd
import subprocess


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def main():
    marker = dict(line.split('=', 1) for line in pathlib.Path('/etc/widows-sons-environment').read_text().splitlines() if '=' in line)
    if marker.get('VMID') != '20000' or marker.get('PROJECT') != 'widows-sons' or run('hostname', capture_output=True).stdout.strip() != 'can-widows-sons-dev':
        raise RuntimeError('This installer is restricted to the dedicated Widows Sons Canada VM20000')
    root = pathlib.Path(__file__).resolve().parent.parent
    if not (root / 'backend/mobile_app.py').is_file():
        raise RuntimeError('Mobile API source is missing')
    try:
        pwd.getpwnam('widowsapp')
    except KeyError:
        run('useradd', '--system', '--home-dir', '/var/lib/widowsapp', '--create-home', '--shell', '/usr/sbin/nologin', 'widowsapp')
    run('runuser', '-u', 'postgres', '--', 'psql', '-v', 'ON_ERROR_STOP=1', '-d', 'widowssons', '-f', str(root / 'backend/mobile_schema.sql'))
    run('runuser', '-u', 'postgres', '--', 'psql', '-v', 'ON_ERROR_STOP=1', '-d', 'widowssons', '-f', str(root / 'backend/community_schema.sql'))
    run('runuser', '-u', 'postgres', '--', 'psql', '-v', 'ON_ERROR_STOP=1', '-d', 'widowssons', '-f', str(root / 'backend/ride_schema.sql'))
    grants = """
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='widowsapp')
 THEN CREATE ROLE widowsapp LOGIN; END IF; END $$;
GRANT CONNECT ON DATABASE widowssons TO widowsapp;
GRANT USAGE ON SCHEMA public TO widowsapp;
GRANT SELECT ON organisations,members,mobile_invites,mobile_sessions,mobile_rsvps,mobile_auth_attempts TO widowsapp;
GRANT UPDATE(status) ON members TO widowsapp;
GRANT UPDATE(used_at) ON mobile_invites TO widowsapp;
GRANT INSERT ON mobile_sessions,mobile_rsvps,mobile_auth_attempts,audit_events TO widowsapp;
GRANT UPDATE(revoked_at) ON mobile_sessions TO widowsapp;
GRANT UPDATE(response,updated_at) ON mobile_rsvps TO widowsapp;
GRANT UPDATE(attempts),DELETE ON mobile_auth_attempts TO widowsapp;
GRANT USAGE ON SEQUENCE audit_events_id_seq TO widowsapp;
GRANT SELECT,INSERT,UPDATE ON conversations,conversation_messages,conversation_reads,member_blocks,message_reports,live_riders,voice_grants TO widowsapp;
GRANT DELETE ON member_blocks,live_riders,voice_grants TO widowsapp;
GRANT USAGE ON SEQUENCE conversation_messages_id_seq TO widowsapp;
GRANT SELECT ON ride_managers,role_grants TO widowsapp;
GRANT SELECT,INSERT,UPDATE ON ride_plans,ride_assignments,ride_participation,ride_incidents,ride_incident_receipts TO widowsapp;
GRANT SELECT,INSERT ON ride_activity TO widowsapp;
GRANT USAGE ON SEQUENCE ride_activity_id_seq TO widowsapp;
"""
    run('runuser', '-u', 'postgres', '--', 'psql', '-v', 'ON_ERROR_STOP=1', '-d', 'widowssons', input=grants)
    run('/srv/widows-sons/venv/bin/pip', 'install', '-r', str(root / 'backend/requirements.txt'))
    service = f"""[Unit]
Description=Widows Sons mobile API - Canada VM20000
After=network.target postgresql.service nginx.service

[Service]
User=widowsapp
Group=widowsapp
WorkingDirectory={root}/backend
Environment="WIDOWS_SONS_MOBILE_DSN=dbname=widowssons user=widowsapp host=/var/run/postgresql"
Environment=PYTHONDONTWRITEBYTECODE=1
ExecStart=/srv/widows-sons/venv/bin/uvicorn mobile_app:app --host 127.0.0.1 --port 8009 --proxy-headers --forwarded-allow-ips 127.0.0.1 --no-access-log
Restart=on-failure
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
RestrictSUIDSGID=true
LockPersonality=true

[Install]
WantedBy=multi-user.target
"""
    pathlib.Path('/etc/systemd/system/widows-sons-mobile.service').write_text(service)
    nginx = pathlib.Path('/etc/nginx/sites-available/widows-sons')
    original = nginx.read_text()
    if 'location /api/v1/mobile/' not in original:
        anchor = '    location /api/ {'
        assert anchor in original, 'Expected Widows Sons API location was not found'
        snippet = '''    location /api/v1/mobile/ {
        proxy_pass http://127.0.0.1:8009;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
        proxy_connect_timeout 5s;
        proxy_read_timeout 30s;
        client_max_body_size 4k;
        access_log off;
    }
'''
        backup = nginx.with_suffix('.before-mobile')
        if not backup.exists():
            backup.write_text(original)
        nginx.write_text(original.replace(anchor, snippet + anchor))
        try:
            run('nginx', '-t')
        except Exception:
            nginx.write_text(original)
            raise
    else:
        run('nginx', '-t')
    run('systemctl', 'daemon-reload')
    run('systemctl', 'enable', '--now', 'widows-sons-mobile.service')
    run('systemctl', 'restart', 'widows-sons-mobile.service')
    run('systemctl', 'reload', 'nginx')
    print('Widows Sons mobile API installed. Existing public API database permissions are unchanged.')


if __name__ == '__main__':
    main()
