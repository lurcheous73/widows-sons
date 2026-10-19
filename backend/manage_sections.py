"""Operator-only bootstrap of chapter section.manage. No private-content grant.

Run as postgres; delegation is explicit, reasoned and audited. The member must
also be an active moderator of a section to change its access configuration.
"""
import argparse
import os
from uuid import UUID

import psycopg
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['grant', 'revoke'])
    parser.add_argument('--organisation', default='lr')
    parser.add_argument('--member', type=UUID, required=True)
    parser.add_argument('--reason', required=True)
    args = parser.parse_args()
    if len(args.reason.strip()) < 10:
        parser.error('Give a reason of at least ten characters.')
    with psycopg.connect(os.environ.get('WIDOWS_SONS_ADMIN_DSN', 'dbname=widowssons user=postgres host=/var/run/postgresql'), row_factory=dict_row) as db:
        member = db.execute("SELECT m.id,m.organisation_id FROM members m JOIN organisations o ON o.id=m.organisation_id WHERE o.slug=%s AND m.id=%s AND m.status='active' FOR UPDATE", (args.organisation, args.member)).fetchone()
        if not member:
            raise ValueError('Active chapter member not found')
        db.execute('SELECT pg_advisory_xact_lock(hashtextextended(%s,0))', ('section.manage:' + str(args.member),))
        db.execute("DELETE FROM role_grants WHERE organisation_id=%s AND member_id=%s AND capability='section.manage' AND scope_type='organisation' AND scope_id IS NULL", (member['organisation_id'], member['id']))
        if args.action == 'grant':
            db.execute("INSERT INTO role_grants(organisation_id,member_id,capability) VALUES(%s,%s,'section.manage')", (member['organisation_id'], member['id']))
        db.execute('INSERT INTO audit_events(organisation_id,action,target_id,details) VALUES(%s,%s,%s,%s)', (member['organisation_id'], 'section.manager.' + args.action, member['id'], Jsonb({'reason': args.reason.strip(), 'operator': os.getuid()})))
    print('Chapter section configuration permission updated and audited. No existing section membership was granted.')


if __name__ == '__main__':
    main()
