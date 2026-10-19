"""Real PostgreSQL communications checks; never use a production database."""
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import jwt
import psycopg
import pytest
from fastapi.testclient import TestClient
import mobile_app as api
from test_mobile import TEST_DSN, database, invite, activate

pytestmark = pytest.mark.skipif(not TEST_DSN, reason='A disposable PostgreSQL test database is required')
BASE = '/api/v1/mobile/lr'


def person(client, name='QA rider', slug='lr'):
    code, org, member = invite(slug=slug)
    with psycopg.connect(TEST_DSN) as db:
        db.execute('UPDATE members SET display_name=%s WHERE id=%s', (name, member))
    if slug == 'lr':
        auth = activate(client, code)
    else:
        token = 'wss_' + str(uuid4()) + str(uuid4())
        with psycopg.connect(TEST_DSN) as db:
            db.execute("UPDATE members SET status='active' WHERE id=%s", (member,))
            db.execute("INSERT INTO mobile_sessions VALUES(%s,%s,%s,now()+interval '1 day',NULL)", (api.digest(token), org, member))
        auth = {'Authorization': 'Bearer ' + token}
    return auth, org, member


def chapter_room(client, auth):
    result = client.get(BASE + '/conversations', headers=auth)
    assert result.status_code == 200, result.text
    return next(c['id'] for c in result.json()['conversations'] if c['kind'] == 'chapter')


def send(client, auth, room, text='QA message', client_id=None):
    return client.post(BASE + f'/conversations/{room}/messages', headers=auth,
                       json={'client_id': str(client_id or uuid4()), 'body': text})


def going(client, auth):
    result = client.put(BASE + '/events/cms-42/rsvp', headers=auth, json={'response': 'going'})
    assert result.status_code == 200, result.text


def join(client, auth):
    going(client, auth)
    result = client.post(BASE + '/rides/cms-42/join', headers=auth, json={})
    assert result.status_code == 200, result.text
    return result.json()


def sharing(client, auth):
    result = client.post(BASE + '/rides/cms-42/sharing', headers=auth)
    assert result.status_code == 200, result.text
    return result.json()['sharing_id']


def fix(sharing_id=None, **updates):
    result = {'sharing_id': sharing_id or str(uuid4()), 'latitude': 52.63, 'longitude': -1.13, 'accuracy': 12,
              'captured_at': datetime.now(timezone.utc).isoformat()}
    result.update(updates)
    return result


def test_private_endpoints_require_current_membership():
    c = TestClient(api.app)
    for path in ['/members', '/conversations', '/rides/cms-42/live']:
        assert c.get(BASE + path).status_code == 401
    auth, org, member = person(c)
    with psycopg.connect(TEST_DSN) as db:
        db.execute("UPDATE members SET status='suspended' WHERE id=%s", (member,))
    assert c.get(BASE + '/members', headers=auth).status_code == 401


def test_directory_exposes_only_chapter_active_names_and_own_block_state():
    c = TestClient(api.app)
    auth, _, me = person(c)
    _, _, second = person(c, 'Second QA rider')
    person(c, 'Other chapter', 'other')
    invite(status='suspended')
    data = c.get(BASE + '/members', headers=auth).json()
    assert data == {'members': [{'id': str(second), 'display_name': 'Second QA rider', 'blocked': False}]}
    assert 'email' not in str(data) and str(me) not in str(data)


def test_direct_rooms_are_pair_unique_and_tenant_private():
    c = TestClient(api.app)
    a, _, first = person(c)
    b, _, second = person(c)
    third, _, _ = person(c)
    other, _, outsider = person(c, slug='other')
    one = c.post(BASE + '/conversations/direct', headers=a, json={'member_id': str(second)})
    assert one.status_code == 200, one.text
    room = one.json()['id']
    assert c.post(BASE + '/conversations/direct', headers=b, json={'member_id': str(first)}).json()['id'] == room
    assert send(c, a, room).status_code == 200
    path = BASE + f'/conversations/{room}/messages'
    assert c.get(path, headers=b).status_code == 200
    assert c.get(path, headers=third).status_code == 404
    assert c.get(path, headers=other).status_code == 401
    assert c.post(BASE + '/conversations/direct', headers=a, json={'member_id': str(outsider)}).status_code == 404
    assert c.post(BASE + '/conversations/direct', headers=a, json={'member_id': str(first)}).status_code == 404


def test_message_idempotency_and_id_not_reused_across_conversations():
    c = TestClient(api.app)
    a, _, _ = person(c)
    _, _, second = person(c)
    room = chapter_room(c, a)
    key = uuid4()
    first = send(c, a, room, 'First message', key).json()
    assert send(c, a, room, 'Changed retry body', key).json() == first
    assert len(c.get(BASE + f'/conversations/{room}/messages', headers=a).json()['messages']) == 1
    dm = c.post(BASE + '/conversations/direct', headers=a, json={'member_id': str(second)}).json()['id']
    assert send(c, a, dm, client_id=key).status_code == 409


def test_message_validation_tombstones_and_ownership():
    c = TestClient(api.app)
    a, _, _ = person(c)
    b, _, _ = person(c)
    room = chapter_room(c, a)
    for value in [' ', 'x' * 2001, 'bad\x00text']:
        assert send(c, a, room, value).status_code == 422
    message = send(c, a, room, '  Hello\nchapter  ').json()
    assert message['body'] == 'Hello\nchapter'
    path = BASE + f"/conversations/{room}/messages/{message['id']}"
    assert c.delete(path, headers=b).status_code == 404
    assert c.delete(path, headers=a).status_code == 204
    tombstone = c.get(BASE + f'/conversations/{room}/messages', headers=b).json()['messages'][0]
    assert tombstone['body'] == '' and tombstone['deleted'] is True


def test_unread_cursor_and_history_pagination():
    c = TestClient(api.app)
    a, _, _ = person(c)
    b, _, _ = person(c)
    room = chapter_room(c, a)
    ids = [send(c, a, room, str(i)).json()['id'] for i in range(3)]
    assert c.get(BASE + '/conversations', headers=b).json()['conversations'][0]['unread'] == 3
    assert c.put(BASE + f'/conversations/{room}/read', headers=b, json={'message_id': ids[1]}).status_code == 204
    assert c.get(BASE + '/conversations', headers=b).json()['conversations'][0]['unread'] == 1
    assert [m['id'] for m in c.get(BASE + f'/conversations/{room}/messages?before={ids[1]}', headers=b).json()['messages']] == ids[:1]
    assert [m['id'] for m in c.get(BASE + f'/conversations/{room}/messages?after={ids[1]}', headers=b).json()['messages']] == ids[2:]


def test_direct_blocking_is_symmetric_and_unblocking_is_owned():
    c = TestClient(api.app)
    a, _, first = person(c)
    b, _, second = person(c)
    room = c.post(BASE + '/conversations/direct', headers=a, json={'member_id': str(second)}).json()['id']
    assert c.put(BASE + f'/members/{second}/block', headers=a).status_code == 204
    assert send(c, b, room).status_code == 403
    assert send(c, a, room).status_code == 403
    c.delete(BASE + f'/members/{first}/block', headers=b)
    assert send(c, b, room).status_code == 403
    c.delete(BASE + f'/members/{second}/block', headers=a)
    assert send(c, b, room).status_code == 200


def test_message_reports_do_not_give_access_to_other_direct_rooms():
    c = TestClient(api.app)
    a, _, _ = person(c)
    b, _, second = person(c)
    outsider, _, _ = person(c)
    room = c.post(BASE + '/conversations/direct', headers=a, json={'member_id': str(second)}).json()['id']
    message = send(c, a, room).json()
    path = BASE + f"/conversations/{room}/messages/{message['id']}/report"
    assert c.post(path, headers=outsider, json={'reason': 'Test report'}).status_code == 404
    assert c.post(path, headers=b, json={'reason': 'Test report'}).status_code == 204
    assert c.post(path, headers=b, json={'reason': 'Duplicate'}).status_code == 204
    with psycopg.connect(TEST_DSN) as db:
        assert db.execute('SELECT count(*) FROM message_reports').fetchone()[0] == 1


def test_ride_chat_requires_rsvp_and_live_mode_requires_going():
    c = TestClient(api.app)
    a, _, _ = person(c)
    assert c.post(BASE + '/rides/cms-42/conversation', headers=a).status_code == 403
    assert c.post(BASE + '/rides/cms-42/join', headers=a, json={}).status_code == 403
    c.put(BASE + '/events/cms-42/rsvp', headers=a, json={'response': 'interested'})
    assert c.post(BASE + '/rides/cms-42/conversation', headers=a).status_code == 200
    assert c.post(BASE + '/rides/cms-42/join', headers=a, json={}).status_code == 403
    going(c, a)
    assert c.post(BASE + '/rides/cms-42/join', headers=a, json={'minutes': 481}).status_code == 422
    assert c.post(BASE + '/rides/cms-999/join', headers=a, json={}).status_code == 404


def test_live_join_is_time_limited_and_never_implies_location_consent():
    c = TestClient(api.app)
    a, _, first = person(c)
    outsider, _, _ = person(c)
    result = join(c, a)
    assert datetime.fromisoformat(result['expires_at']) <= datetime.now(timezone.utc) + timedelta(hours=4, seconds=1)
    state = c.get(BASE + '/rides/cms-42/live', headers=a).json()
    assert state['riders'][0]['sharing'] is False and state['riders'][0]['latitude'] is None
    assert c.get(BASE + '/rides/cms-42/live', headers=outsider).status_code == 403
    assert state['riders'][0]['id'] == str(first)


def test_position_updates_validate_accuracy_age_and_order():
    c = TestClient(api.app)
    a, _, _ = person(c)
    join(c, a)
    path = BASE + '/rides/cms-42/position'
    for invalid in [fix(latitude=91), fix(accuracy=-1), fix(accuracy=1001), fix(captured_at=datetime.now().isoformat()), fix(captured_at=(datetime.now(timezone.utc)-timedelta(minutes=3)).isoformat())]:
        assert c.put(path, headers=a, json=invalid).status_code == 422
    value = fix(sharing(c, a))
    assert c.put(path, headers=a, json=value).status_code == 204
    assert c.put(path, headers=a, json=value).status_code == 409
    own = c.get(BASE + '/rides/cms-42/live', headers=a).json()['riders'][0]
    assert own['sharing'] is True and own['latitude'] == value['latitude']


@pytest.mark.parametrize('action', ['stop', 'home', 'left'])
def test_stop_and_home_remove_coordinates_immediately(action):
    c = TestClient(api.app)
    a, _, first = person(c)
    b, _, _ = person(c)
    join(c, a)
    join(c, b)
    assert c.put(BASE + '/rides/cms-42/position', headers=a, json=fix(sharing(c, a))).status_code == 204
    if action == 'stop':
        assert c.delete(BASE + '/rides/cms-42/position', headers=a).status_code == 204
    else:
        assert c.post(BASE + '/rides/cms-42/end', headers=a, json={'state': action}).status_code == 204
    rider = next(r for r in c.get(BASE + '/rides/cms-42/live', headers=b).json()['riders'] if r['id'] == str(first))
    assert rider['latitude'] is None and rider['longitude'] is None and rider['sharing'] is False
    if action != 'stop':
        assert rider['state'] == action
        assert c.put(BASE + '/rides/cms-42/position', headers=a, json=fix()).status_code == 403


def test_stale_revoked_and_suspended_riders_cannot_expose_positions():
    c = TestClient(api.app)
    a, _, first = person(c)
    b, _, _ = person(c)
    join(c, a)
    join(c, b)
    assert c.put(BASE + '/rides/cms-42/position', headers=a, json=fix(sharing(c, a))).status_code == 204
    with psycopg.connect(TEST_DSN) as db:
        db.execute("UPDATE live_riders SET received_at=now()-interval '3 minutes' WHERE member_id=%s", (first,))
    assert next(r for r in c.get(BASE + '/rides/cms-42/live', headers=b).json()['riders'] if r['id'] == str(first))['latitude'] is None
    api.app.state.community_cleanup()
    with psycopg.connect(TEST_DSN) as db:
        assert db.execute('SELECT latitude,sharing FROM live_riders WHERE member_id=%s', (first,)).fetchone() == (None, True)
        db.execute("UPDATE members SET status='suspended' WHERE id=%s", (first,))
    assert str(first) not in str(c.get(BASE + '/rides/cms-42/live', headers=b).json()['riders'])


def test_voice_tokens_only_allow_microphone_in_one_room_and_expire(monkeypatch):
    monkeypatch.setenv('WIDOWS_SONS_VOICE_KEY', 'qa-key')
    secret = 'qa-only-secret-not-a-production-key-' * 2
    monkeypatch.setenv('WIDOWS_SONS_VOICE_SECRET', secret)
    c = TestClient(api.app)
    a, _, _ = person(c)
    result = c.post(BASE + '/voice', headers=a, json={})
    assert result.status_code == 200, result.text
    data = result.json()
    token = jwt.decode(data['token'], secret, algorithms=['HS256'], issuer='qa-key')
    assert token['video']['room'] == data['room_name']
    assert token['video']['roomJoin'] is True
    assert token['video']['canPublishSources'] == ['microphone']
    assert token['video']['canPublishData'] is False
    assert token['exp']-token['nbf'] <= 90
    assert c.post(BASE + '/voice', headers=a, json={'event_id': 'cms-42'}).status_code == 403
    join(c, a)
    ride = c.post(BASE + '/voice', headers=a, json={'event_id': 'cms-42'}).json()
    assert ride['room_name'] != data['room_name'] and ride['room_name'].endswith('-cms-42')
    assert c.delete(BASE + '/voice/' + ride['grant_id'], headers=a).status_code == 204
    assert len(api.app.state.community_cleanup()) == 2


def test_message_and_position_mutations_fail_after_session_revocation():
    c = TestClient(api.app)
    a, _, _ = person(c)
    room = chapter_room(c, a)
    join(c, a)
    c.delete(BASE + '/session', headers=a)
    assert send(c, a, room).status_code == 401
    assert c.put(BASE + '/rides/cms-42/position', headers=a, json=fix()).status_code == 401


def test_stopped_sharing_lease_cannot_be_restarted_by_an_inflight_position():
    c = TestClient(api.app)
    a, _, _ = person(c)
    join(c, a)
    old = sharing(c, a)
    assert c.put(BASE + '/rides/cms-42/position', headers=a, json=fix(old)).status_code == 204
    c.delete(BASE + '/rides/cms-42/position', headers=a)
    assert c.put(BASE + '/rides/cms-42/position', headers=a, json=fix(old)).status_code == 409
    new = sharing(c, a)
    assert new != old
    assert c.put(BASE + '/rides/cms-42/position', headers=a, json=fix(old)).status_code == 409
    assert c.put(BASE + '/rides/cms-42/position', headers=a, json=fix(new)).status_code == 204


def test_changing_rsvp_ends_live_sharing_and_clears_the_position():
    c = TestClient(api.app)
    a, _, first = person(c)
    join(c, a)
    value = fix(sharing(c, a))
    assert c.put(BASE + '/rides/cms-42/position', headers=a, json=value).status_code == 204
    assert c.put(BASE + '/events/cms-42/rsvp', headers=a, json={'response': 'not_going'}).status_code == 200
    assert c.get(BASE + '/rides/cms-42/live', headers=a).status_code == 403
    with psycopg.connect(TEST_DSN) as db:
        assert db.execute('SELECT latitude,sharing,sharing_id,state FROM live_riders WHERE member_id=%s', (first,)).fetchone() == (None, False, None, 'left')


def test_voice_reconnect_gate_rejects_revoked_grants_and_refreshed_tokens(monkeypatch):
    secret = 'qa-gate-secret-' * 5
    monkeypatch.setenv('WIDOWS_SONS_VOICE_KEY', 'qa-key')
    monkeypatch.setenv('WIDOWS_SONS_VOICE_SECRET', secret)
    c = TestClient(api.app, client=('127.0.0.1', 12345))
    auth, _, _ = person(c)
    result = c.post(BASE + '/voice', headers=auth, json={}).json()
    headers = {'X-Original-URI': '/rtc?access_token=' + result['token']}
    assert c.get('/internal/voice-authorize', headers=headers).status_code == 204
    assert TestClient(api.app).get('/internal/voice-authorize', headers=headers).status_code == 403
    claims = jwt.decode(result['token'], secret, algorithms=['HS256'], issuer='qa-key')
    claims['exp'] += 600  # Simulate the SFU's renewed token for the same identity.
    renewed = jwt.encode(claims, secret, algorithm='HS256')
    c.delete(BASE + '/voice/' + result['grant_id'], headers=auth)
    assert c.get('/internal/voice-authorize', headers={'X-Original-URI': '/rtc?access_token=' + renewed}).status_code == 401
    assert c.get('/internal/voice-authorize', headers=headers).status_code == 401


def test_voice_admission_requires_current_session_and_exact_room(monkeypatch):
    secret = 'qa-admission-secret-' * 5
    monkeypatch.setenv('WIDOWS_SONS_VOICE_KEY', 'qa-key')
    monkeypatch.setenv('WIDOWS_SONS_VOICE_SECRET', secret)
    c = TestClient(api.app, client=('127.0.0.1', 12345))
    auth, _, _ = person(c)
    result = c.post(BASE + '/voice', headers=auth, json={}).json()
    claims = jwt.decode(result['token'], secret, algorithms=['HS256'], issuer='qa-key')
    claims['video']['room'] = 'another-room'
    wrong_room = jwt.encode(claims, secret, algorithm='HS256')
    assert c.get('/internal/voice-authorize', headers={'X-Original-URI': '/rtc?access_token=' + wrong_room}).status_code == 401
    c.delete(BASE + '/session', headers=auth)
    assert c.get('/internal/voice-authorize', headers={'X-Original-URI': '/rtc?access_token=' + result['token']}).status_code == 401


def test_voice_identity_check_rejects_deleted_members_even_after_grant_cascade(monkeypatch):
    secret = 'qa-delete-secret-' * 5
    monkeypatch.setenv('WIDOWS_SONS_VOICE_KEY', 'qa-key')
    monkeypatch.setenv('WIDOWS_SONS_VOICE_SECRET', secret)
    c = TestClient(api.app)
    auth, _, member = person(c)
    result = c.post(BASE + '/voice', headers=auth, json={}).json()
    claims = jwt.decode(result['token'], secret, algorithms=['HS256'], issuer='qa-key')
    assert api.app.state.community_active_voice_identity(result['room_name'], claims['sub'])
    with psycopg.connect(TEST_DSN) as db:
        db.execute('DELETE FROM members WHERE id=%s', (member,))
        assert db.execute('SELECT count(*) FROM voice_grants').fetchone()[0] == 0
    assert not api.app.state.community_active_voice_identity(result['room_name'], claims['sub'])
