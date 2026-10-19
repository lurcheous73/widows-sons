"""Operator-only invitation provisioning. Run as postgres on VM20000.

python manage_mobile.py invite --email member@example.invalid --name 'Test Member'
    --out /secure/path/invitation.json
Share the single-use code privately with that approved member. No email is sent.
"""
import argparse
import json
import os
import secrets
from datetime import datetime, timedelta, timezone
from pathlib import Path

import psycopg
from psycopg.rows import dict_row
from mobile_app import digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['invite'])
    parser.add_argument('--organisation', default='lr')
    parser.add_argument('--email', required=True)
    parser.add_argument('--name', required=True)
    parser.add_argument('--type', choices=['member', 'associate', 'guest'], default='member')
    parser.add_argument('--out', type=Path, required=True, help='New private output file; refuses overwrites')
    args = parser.parse_args()
    if '@' not in args.email or len(args.email) > 254 or not 1 <= len(args.name.strip()) <= 150:
        parser.error('Supply a valid email and a name of 1–150 characters.')
    # Reserve the destination before creating a secret. Existing files are never overwritten.
    fd = os.open(args.out, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with psycopg.connect(os.environ.get('WIDOWS_SONS_ADMIN_DSN', 'dbname=widowssons user=postgres host=/var/run/postgresql'), row_factory=dict_row) as db:
            org = db.execute('SELECT id FROM organisations WHERE slug=%s', (args.organisation,)).fetchone()
            if not org:
                raise ValueError('Chapter not found')
            member = db.execute('SELECT id,status FROM members WHERE organisation_id=%s AND lower(email)=lower(%s) FOR UPDATE', (org['id'], args.email)).fetchone()
            if member and member['status'] not in ('active', 'invited'):
                raise ValueError('Suspended or former members cannot receive an invitation')
            if not member:
                member = db.execute('INSERT INTO members(organisation_id,email,display_name,membership_type) VALUES(%s,%s,%s,%s) RETURNING id', (org['id'], args.email.lower(), args.name.strip(), args.type)).fetchone()
            token = 'wsi_' + secrets.token_urlsafe(32)
            expires = datetime.now(timezone.utc) + timedelta(days=7)
            db.execute('DELETE FROM mobile_invites WHERE organisation_id=%s AND member_id=%s', (org['id'], member['id']))
            db.execute('INSERT INTO mobile_invites(token_hash,organisation_id,member_id,expires_at) VALUES(%s,%s,%s,%s)', (digest(token), org['id'], member['id'], expires))
            db.execute("INSERT INTO audit_events(organisation_id,action,target_id) VALUES(%s,'mobile.invite',%s)", (org['id'], member['id']))
            with os.fdopen(fd, 'w') as stream:
                fd = None
                json.dump({'chapter': args.organisation, 'invitation': token, 'expires_at': expires.isoformat()}, stream, indent=2)
        print('Invitation written to the private file. It expires in seven days and can be used once.')
    except Exception:
        if fd is not None:
            os.close(fd)
        args.out.unlink(missing_ok=True)
        raise


if __name__ == '__main__':
    main()
