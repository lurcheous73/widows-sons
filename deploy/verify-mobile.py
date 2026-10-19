#!/usr/bin/env python3
"""Exercise the deployed mobile service and its real database permissions.

Run as root on Canada VM20000. A clearly named temporary member and temporary
published event are removed in finally blocks. No mail is sent or real identities
used. The HTTP session and invitation are held in memory, never printed.
"""
import json
import pathlib
import secrets
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / 'backend'))
import psycopg
from mobile_app import digest

checks = []


def db(sql, params=(), fetch=False):
    # Peer authentication remains in use; connect as the postgres OS user.
    script = """import json,sys,psycopg
data=json.load(sys.stdin)
with psycopg.connect('dbname=widowssons user=postgres host=/var/run/postgresql') as c:
 r=c.execute(data['sql'],data['params'])
 print(json.dumps(r.fetchall() if data['fetch'] else [],default=str))
"""
    result = subprocess.run(['runuser', '-u', 'postgres', '--', '/srv/widows-sons/venv/bin/python', '-c', script], input=json.dumps({'sql': sql, 'params': params, 'fetch': fetch}, default=str), capture_output=True, text=True, check=True)
    return json.loads(result.stdout)


def wp(*args):
    return subprocess.check_output(['php', '/srv/widows-sons/wp-cli.phar', '--allow-root', '--path=/srv/widows-sons/wordpress', *args], text=True).strip()


def request(path, method='GET', data=None, token=None):
    headers = {'Host': 'wsmba.the-grange.uk', 'X-Forwarded-Proto': 'https', 'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    req = urllib.request.Request('http://127.0.0.1:8080/api/v1/mobile/' + path, method=method, headers=headers, data=json.dumps(data).encode() if data is not None else None)
    try:
        response = urllib.request.urlopen(req, timeout=30)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        body = response.read()
        return response.status, json.loads(body) if body else None


def check(label, value):
    assert value, label
    checks.append(label)


def main():
    marker = pathlib.Path('/etc/widows-sons-environment').read_text()
    assert 'VMID=20000' in marker and 'PROJECT=widows-sons' in marker
    org = db("SELECT id FROM organisations WHERE slug='lr'", fetch=True)[0][0]
    member = event = None
    code = 'wsi_' + secrets.token_urlsafe(32)
    try:
        member = db('INSERT INTO members(organisation_id,email,display_name) VALUES(%s,%s,%s) RETURNING id', (org, 'mobile-verify-' + secrets.token_hex(8) + '@example.invalid', 'Temporary app verification fixture'), True)[0][0]
        db('INSERT INTO mobile_invites(token_hash,organisation_id,member_id,expires_at) VALUES(%s,%s,%s,%s)', (digest(code), org, member, datetime.now(timezone.utc) + timedelta(hours=1)))
        event = wp('post', 'create', '--post_type=ws_event', '--post_status=publish', '--post_title=Temporary app verification fixture', '--post_content=Automated verification only. This entry is removed immediately.', '--porcelain')
        wp('post', 'meta', 'update', event, '_ws_starts_at', '2099-01-01T10:00')
        wp('post', 'meta', 'update', event, '_ws_location', 'Temporary test location')
        status, feed = request('lr/feed')
        check('Live WordPress feed through VM Nginx', status == 200 and feed['chapter']['slug'] == 'lr')
        check('Published event is available to the app', any(e['id'] == 'cms-' + event for e in feed['events']))
        check('Anonymous profile rejected', request('lr/me')[0] == 401)
        status, session = request('lr/activate', 'POST', {'code': code})
        check('Single-use invitation activates through service database role', status == 200)
        token = session['token']
        check('Invitation reuse rejected', request('lr/activate', 'POST', {'code': code})[0] == 401)
        status, profile = request('lr/me', token=token)
        check('Private profile contains only the authenticated member', status == 200 and profile['id'] == member and 'email' not in profile)
        check('Wrong chapter cannot read a session', request('other/me', token=token)[0] == 401)
        for response in ('going', 'interested', 'not_going'):
            status, _ = request('lr/events/cms-' + event + '/rsvp', 'PUT', {'response': response}, token)
            check('RSVP ' + response + ' persists', status == 200 and request('lr/me', token=token)[1]['rsvps']['cms-' + event] == response)
        check('Unknown event cannot receive RSVP', request('lr/events/cms-999999999/rsvp', 'PUT', {'response': 'going'}, token)[0] == 404)
        check('Sign out revokes the server session', request('lr/session', 'DELETE', token=token)[0] == 204 and request('lr/me', token=token)[0] == 401)
        check('Original public API still cannot read members', db("SELECT has_table_privilege('widowsapi','members','SELECT')", fetch=True)[0][0] is False)
        check('Mobile service cannot read welfare sections or administer members', db("SELECT has_table_privilege('widowsapp','section_members','SELECT'),has_table_privilege('widowsapp','members','INSERT')", fetch=True)[0] == [False, False])
    finally:
        if event:
            wp('post', 'delete', event, '--force')
        if member:
            db('DELETE FROM audit_events WHERE organisation_id=%s AND (actor_id=%s OR target_id=%s)', (org, member, member))
            db('DELETE FROM members WHERE organisation_id=%s AND id=%s', (org, member))
    status, clean = request('lr/feed')
    check('Temporary public event removed', status == 200 and not any(e['id'] == 'cms-' + event for e in clean['events']))
    print(json.dumps({'passed': len(checks), 'checks': checks, 'temporary_fixtures_removed': True}, indent=2))


if __name__ == '__main__':
    main()
