"""Operator-only event.manage delegation. Never implied by a road assignment.

Run as postgres on VM20000. Pass a member UUID, a published CMS event identifier
and a reason. This command does not create invitations or contact anyone.
"""
import argparse
import os
from uuid import UUID

import psycopg
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('action', choices=['grant', 'revoke'])
    p.add_argument('--organisation', default='lr')
    p.add_argument('--member', type=UUID, required=True)
    p.add_argument('--event', required=True, help='cms-NNN; grants only this event')
    p.add_argument('--reason', required=True)
    args = p.parse_args()
    if not args.event.startswith('cms-') or not args.event[4:].isdigit() or len(args.reason.strip()) < 10:
        p.error('Supply a CMS event identifier and a reason of at least ten characters.')
    with psycopg.connect(os.environ.get('WIDOWS_SONS_ADMIN_DSN', 'dbname=widowssons user=postgres host=/var/run/postgresql'), row_factory=dict_row) as db:
        member = db.execute("SELECT m.id,m.organisation_id FROM members m JOIN organisations o ON o.id=m.organisation_id WHERE o.slug=%s AND m.id=%s AND m.status='active' FOR UPDATE", (args.organisation, args.member)).fetchone()
        if not member:
            raise ValueError('Active chapter member not found')
        if args.action == 'grant':
            db.execute('INSERT INTO ride_managers(organisation_id,event_id,member_id) VALUES(%s,%s,%s) ON CONFLICT DO NOTHING', (member['organisation_id'], args.event, args.member))
        else:
            db.execute('DELETE FROM ride_managers WHERE organisation_id=%s AND event_id=%s AND member_id=%s', (member['organisation_id'], args.event, args.member))
        db.execute('INSERT INTO audit_events(organisation_id,action,target_id,details) VALUES(%s,%s,%s,%s)', (member['organisation_id'], 'ride.manager.' + args.action, args.member, Jsonb({'event_id': args.event, 'reason': args.reason.strip(), 'operator': os.getuid()})))
    print('Event-scoped organiser permission updated and audited. No road role was assigned.')


if __name__ == '__main__':
    main()
