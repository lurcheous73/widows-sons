"""Exercise real PostgreSQL authority, content and poll state transitions."""
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import psycopg
import pytest
from fastapi.testclient import TestClient
import mobile_app as api
from test_mobile import TEST_DSN, database, invite, activate

pytestmark = pytest.mark.skipif(not TEST_DSN, reason='Disposable PostgreSQL is required')
BASE = '/api/v1/mobile/lr/sections'


def setup(policy='approval'):
    client = TestClient(api.app)
    people = []
    for _ in range(4):
        code, org, mid = invite()
        people.append((activate(client, code), mid))
    with psycopg.connect(TEST_DSN) as db:
        db.execute("INSERT INTO role_grants(organisation_id,member_id,capability) VALUES(%s,%s,'section.manage')", (org, people[0][1]))
    result = client.post(BASE, headers=people[0][0], json={'title': 'QA Social', 'description': 'An optional chapter group', 'join_policy': policy})
    assert result.status_code == 200, result.text
    return client, result.json()['id'], org, people


def join(client, sid, auth):
    return client.post(BASE + '/' + sid + '/join', headers=auth)


def act(client, sid, moderator, target, action):
    return client.put(BASE + '/' + sid + '/members/' + str(target), headers=moderator, json={'action': action})


def post(client, sid, auth, **values):
    return client.post(BASE + '/' + sid + '/posts', headers=auth, json={'client_id': str(uuid4()), 'kind': 'discussion', 'title': 'Sunday coffee', 'body': 'Meet after the chapter ride.', **values})


def enrol(client, sid, people):
    for auth, mid in people[1:]:
        assert join(client, sid, auth).status_code == 204
        assert act(client, sid, people[0][0], mid, 'approve').status_code == 204


def test_guest_cannot_list_sections_and_no_default_groups_are_created():
    assert TestClient(api.app).get(BASE).status_code == 401
    code, _, _ = invite()
    c = TestClient(api.app)
    assert c.get(BASE, headers=activate(c, code)).json() == {'can_create': False, 'sections': []}


def test_creation_requires_capability_and_explicit_creator_membership_only():
    c, sid, _, people = setup()
    assert c.post(BASE, headers=people[1][0], json={'title': 'Group', 'join_policy': 'open'}).status_code == 403
    data = c.get(BASE, headers=people[0][0]).json()
    assert data['can_create'] and data['sections'][0]['can_moderate']
    other = c.get(BASE + '/' + sid, headers=people[1][0]).json()
    assert other['membership'] == 'none' and not other['can_read']


def test_approval_never_discloses_posts_before_acceptance():
    c, sid, _, people = setup()
    post(c, sid, people[0][0])
    assert join(c, sid, people[1][0]).status_code == 204
    assert c.get(BASE + '/' + sid, headers=people[1][0]).json()['membership'] == 'requested'
    assert c.get(BASE + '/' + sid + '/posts', headers=people[1][0]).status_code == 403
    assert act(c, sid, people[1][0], people[1][1], 'approve').status_code == 403
    assert act(c, sid, people[0][0], people[1][1], 'approve').status_code == 204
    assert len(c.get(BASE + '/' + sid + '/posts', headers=people[1][0]).json()['posts']) == 1


def test_private_invitation_hidden_until_invited_and_recipient_must_accept():
    c, sid, _, people = setup('invite')
    assert c.get(BASE, headers=people[1][0]).json()['sections'] == []
    assert c.get(BASE + '/' + sid, headers=people[1][0]).status_code == 404
    assert act(c, sid, people[0][0], people[1][1], 'invite').status_code == 204
    assert not c.get(BASE, headers=people[1][0]).json()['sections'][0]['can_read']
    assert join(c, sid, people[1][0]).status_code == 204
    assert c.get(BASE + '/' + sid + '/posts', headers=people[1][0]).status_code == 200
    assert c.delete(BASE + '/' + sid + '/membership', headers=people[1][0]).status_code == 204
    assert c.get(BASE + '/' + sid, headers=people[1][0]).status_code == 404


def test_open_group_requires_join_removed_member_cannot_rejoin_without_invitation():
    c, sid, _, people = setup('open')
    assert post(c, sid, people[1][0]).status_code == 403
    assert join(c, sid, people[1][0]).status_code == 204
    assert post(c, sid, people[1][0]).status_code == 200
    assert act(c, sid, people[0][0], people[1][1], 'remove').status_code == 204
    assert join(c, sid, people[1][0]).status_code == 403
    assert act(c, sid, people[0][0], people[1][1], 'invite').status_code == 204
    assert join(c, sid, people[1][0]).status_code == 204


def test_general_admin_cannot_read_invite_section_or_reconfigure_without_membership():
    c, sid, org, people = setup('invite')
    with psycopg.connect(TEST_DSN) as db:
        db.execute("INSERT INTO role_grants(organisation_id,member_id,capability) VALUES(%s,%s,'section.manage')", (org, people[1][1]))
    metadata = c.get(BASE, headers=people[1][0]).json()['sections'][0]
    assert not metadata['can_read'] and not metadata['can_configure']
    assert c.get(BASE + '/' + sid + '/posts', headers=people[1][0]).status_code == 403
    assert c.put(BASE + '/' + sid, headers=people[1][0], json={'title': 'Expose', 'join_policy': 'open'}).status_code == 403
    assert c.get(BASE + '/' + sid + '/members', headers=people[1][0]).status_code == 403


def test_tenant_ids_and_composite_foreign_keys_do_not_cross_chapters():
    c, sid, org, people = setup()
    code, _, other_id = invite('other', status='active')
    assert act(c, sid, people[0][0], other_id, 'invite').status_code == 404
    with psycopg.connect(TEST_DSN) as db:
        with pytest.raises(psycopg.errors.ForeignKeyViolation):
            db.execute("INSERT INTO clubhouse_memberships(organisation_id,section_id,member_id,state) VALUES(%s,%s,%s,'active')", (org, sid, other_id))
    assert c.get('/api/v1/mobile/other/sections/' + sid, headers=people[0][0]).status_code == 401
    assert c.get(BASE + '/' + str(uuid4()), headers=people[0][0]).status_code == 404


def test_last_moderator_handover_is_explicit_and_section_scoped():
    c, sid, _, people = setup()
    assert c.delete(BASE + '/' + sid + '/membership', headers=people[0][0]).status_code == 409
    enrol(c, sid, people)
    assert act(c, sid, people[0][0], people[1][1], 'promote').status_code == 204
    assert c.delete(BASE + '/' + sid + '/membership', headers=people[0][0]).status_code == 204
    assert c.get(BASE + '/' + sid + '/members', headers=people[1][0]).status_code == 200
    assert c.get(BASE + '/' + sid + '/moderation', headers=people[0][0]).status_code == 403


def test_renaming_pausing_archiving_and_revision_do_not_change_membership():
    c, sid, _, people = setup()
    enrol(c, sid, people)
    body = {'revision': 0, 'title': 'Families & friends', 'join_policy': 'invite', 'state': 'paused'}
    assert c.put(BASE + '/' + sid, headers=people[0][0], json=body).status_code == 204
    assert c.put(BASE + '/' + sid, headers=people[0][0], json=body).status_code == 409
    assert c.get(BASE + '/' + sid + '/posts', headers=people[1][0]).status_code == 403
    body.update(revision=1, state='archived')
    assert c.put(BASE + '/' + sid, headers=people[0][0], json=body).status_code == 204
    assert c.get(BASE + '/' + sid + '/posts', headers=people[1][0]).status_code == 200
    assert post(c, sid, people[1][0]).status_code == 409


def test_announcement_authority_stable_post_and_comment_retries_and_removal():
    c, sid, _, people = setup()
    enrol(c, sid, people)
    assert post(c, sid, people[1][0], kind='announcement').status_code == 403
    key = str(uuid4())
    first = post(c, sid, people[1][0], client_id=key).json()
    assert post(c, sid, people[1][0], client_id=key, title='Changed retry').json() == first
    url = BASE + '/' + sid + '/posts/' + first['id']
    key2 = str(uuid4())
    a = c.post(url + '/comments', headers=people[2][0], json={'client_id': key2, 'body': 'See you there'}).json()
    assert c.post(url + '/comments', headers=people[2][0], json={'client_id': key2, 'body': 'Changed'}).json() == a
    assert c.post(url + '/actions', headers=people[2][0], json={'action': 'remove', 'reason': 'Not my post'}).status_code == 403
    assert c.post(url + '/comments/' + str(a['id']) + '/remove', headers=people[2][0], json={'reason': 'Changed my mind'}).status_code == 204
    assert c.get(url + '/comments', headers=people[1][0]).json()['comments'][0]['body'] == ''
    assert c.post(url + '/actions', headers=people[1][0], json={'action': 'remove', 'reason': 'Changed my mind'}).status_code == 204
    removed = c.get(url, headers=people[1][0]).json()
    assert removed['removed'] and removed['body'] == ''
    assert c.get(url + '/comments', headers=people[0][0]).json()['comments'] == []


def test_poll_choice_change_withdrawal_counts_closing_and_no_voter_directory():
    c, sid, _, people = setup()
    enrol(c, sid, people)
    poll = post(c, sid, people[1][0], kind='poll', options=['Coffee', 'Lunch'], closes_at=(datetime.now(timezone.utc) + timedelta(days=1)).isoformat()).json()
    url = BASE + '/' + sid + '/posts/' + poll['id']
    vote_url = url + '/vote'
    assert c.put(vote_url, headers=people[2][0], json={'option_id': str(uuid4())}).status_code == 422
    for option in poll['options']:
        assert c.put(vote_url, headers=people[2][0], json={'option_id': option['id']}).status_code == 204
    data = c.get(url, headers=people[2][0]).json()
    assert [v['votes'] for v in data['options']] == [0, 1] and data['my_vote'] == poll['options'][1]['id']
    assert 'voters' not in data and 'member_id' not in str(data['options'])
    assert c.delete(vote_url, headers=people[2][0]).status_code == 204
    assert c.post(url + '/actions', headers=people[1][0], json={'action': 'close'}).status_code == 403
    assert c.post(url + '/actions', headers=people[0][0], json={'action': 'close'}).status_code == 204
    assert c.put(vote_url, headers=people[2][0], json={'option_id': poll['options'][0]['id']}).status_code == 409


@pytest.mark.parametrize('fields', [
    {'title': '   '}, {'body': '\u0000hidden'}, {'kind': 'poll', 'options': ['Yes', 'yes']},
    {'kind': 'poll', 'options': ['One']}, {'options': ['Not a poll']},
    {'kind': 'poll', 'options': ['A', 'B'], 'closes_at': '2026-01-01T00:00:00'},
])
def test_validation_rejects_empty_text_controls_and_invalid_polls(fields):
    c, sid, _, people = setup()
    assert post(c, sid, people[0][0], **fields).status_code == 422


def test_reports_are_scoped_to_section_moderators_and_resolution_is_audited():
    c, sid, _, people = setup()
    enrol(c, sid, people)
    item = post(c, sid, people[1][0]).json()
    url = BASE + '/' + sid
    assert c.post(url + '/posts/' + item['id'] + '/reports', headers=people[2][0], json={'reason': 'Please review this post'}).status_code == 204
    assert c.get(url + '/moderation', headers=people[1][0]).status_code == 403
    report = c.get(url + '/moderation', headers=people[0][0]).json()['reports'][0]
    assert 'member_id' not in report
    assert c.post(url + '/reports/' + report['id'] + '/resolve', headers=people[0][0], json={'reason': 'Discussed with the author'}).status_code == 204
    result = c.get(url + '/moderation', headers=people[0][0]).json()
    assert result['reports'] == [] and result['activity'][0]['action'] == 'report.resolved'


def test_revoked_session_removed_membership_and_ordinary_member_cannot_read_roster():
    c, sid, _, people = setup()
    enrol(c, sid, people)
    assert c.get(BASE + '/' + sid + '/members', headers=people[1][0]).status_code == 403
    assert act(c, sid, people[0][0], people[1][1], 'remove').status_code == 204
    assert c.get(BASE + '/' + sid + '/posts', headers=people[1][0]).status_code == 403
    c.delete('/api/v1/mobile/lr/session', headers=people[2][0])
    assert c.get(BASE + '/' + sid + '/posts', headers=people[2][0]).status_code == 401


def test_pagination_has_no_duplicates_and_cursor_pair_is_required():
    c, sid, org, people = setup()
    with psycopg.connect(TEST_DSN) as db:
        for i in range(32):
            db.execute("INSERT INTO clubhouse_posts(organisation_id,section_id,author_id,client_id,kind,title,body) VALUES(%s,%s,%s,%s,'discussion',%s,'')", (org, sid, people[0][1], uuid4(), str(i)))
    url = BASE + '/' + sid + '/posts'
    first = c.get(url, headers=people[0][0]).json()
    assert len(first['posts']) == 30 and first['has_older']
    last = first['posts'][-1]
    second = c.get(url, headers=people[0][0], params={'before_id': last['id']}).json()
    assert len(second['posts']) == 2 and not second['has_older']
    assert not set(v['id'] for v in first['posts']) & set(v['id'] for v in second['posts'])
    assert c.get(url, headers=people[0][0], params={'before_id': str(uuid4())}).status_code == 404


def test_section_creation_retry_is_idempotent_and_foreign_tenant_session_cannot_open_it():
    import secrets
    c, sid, org, people = setup()
    key = str(uuid4())
    body = {'client_id': key, 'title': 'QA Families', 'join_policy': 'invite'}
    first = c.post(BASE, headers=people[0][0], json=body)
    assert first.status_code == 200
    assert c.post(BASE, headers=people[0][0], json=body).json() == first.json()
    token = 'wss_' + secrets.token_urlsafe(32)
    _, other_org, other_member = invite('other', status='active')
    with psycopg.connect(TEST_DSN) as db:
        db.execute("INSERT INTO mobile_sessions(token_hash,organisation_id,member_id,expires_at) VALUES(%s,%s,%s,now()+interval '1 hour')", (api.digest(token), other_org, other_member))
    auth = {'Authorization': 'Bearer ' + token}
    assert c.get('/api/v1/mobile/other/sections', headers=auth).json()['sections'] == []
    assert c.get('/api/v1/mobile/other/sections/' + sid, headers=auth).status_code == 404
    assert c.get('/api/v1/mobile/other/sections/' + sid + '/posts', headers=auth).status_code == 404
    assert c.get(BASE + '/' + sid, headers=auth).status_code == 401
