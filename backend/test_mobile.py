"""Real PostgreSQL integration checks. ONLY run against a disposable *_test DB.

WIDOWS_SONS_MOBILE_TEST_DSN='dbname=widowssons_mobile_test user=postgres' pytest -q
No production members or CMS posts are created by this suite.
"""
import os
import secrets
from pathlib import Path

import psycopg
import pytest
from fastapi.testclient import TestClient
import mobile_app as api

TEST_DSN = os.environ.get('WIDOWS_SONS_MOBILE_TEST_DSN')
pytestmark = pytest.mark.skipif(not TEST_DSN, reason='A disposable PostgreSQL test database is required')


@pytest.fixture(autouse=True)
def database(monkeypatch):
    assert psycopg.conninfo.conninfo_to_dict(TEST_DSN)['dbname'].endswith('_test')
    monkeypatch.setattr(api, 'DSN', TEST_DSN)
    with psycopg.connect(TEST_DSN) as db:
        db.execute('DROP SCHEMA public CASCADE; CREATE SCHEMA public;')
        db.execute(Path(__file__).with_name('schema.sql').read_text())
        db.execute(Path(__file__).with_name('mobile_schema.sql').read_text())
        db.execute("INSERT INTO organisations(slug,name,display_name) VALUES('other','Other chapter','Other')")
    def cms(path):
        if '/events' in path:
            return {'organisation': 'lr', 'events': [{'id': 'cms-42', 'title': 'Test ride', 'starts_at': '2099-01-01T10:00:00+00:00'}]}
        if '/posts?' in path:
            return [{'id': 10, 'title': {'rendered': 'News &amp; rides'}, 'excerpt': {'rendered': '<p>Welcome</p>'}, 'content': {'rendered': '<p>First</p><script>hidden()</script><p>Second</p>'}, 'date_gmt': '2026-10-19T10:00:00', 'link': 'https://wsmba.the-grange.uk/news/'}]
        return []
    monkeypatch.setattr(api, 'cms', cms)


def invite(slug='lr', status='invited'):
    code = 'wsi_' + secrets.token_urlsafe(32)
    with psycopg.connect(TEST_DSN) as db:
        org = db.execute('SELECT id FROM organisations WHERE slug=%s', (slug,)).fetchone()[0]
        member = db.execute('INSERT INTO members(organisation_id,email,display_name,status) VALUES(%s,%s,%s,%s) RETURNING id', (org, secrets.token_hex(8) + '@example.invalid', 'Test Member', status)).fetchone()[0]
        db.execute("INSERT INTO mobile_invites VALUES(%s,%s,%s,now()+interval '1 day',NULL)", (api.digest(code), org, member))
    return code, org, member


def activate(client, code):
    result = client.post('/api/v1/mobile/lr/activate', json={'code': code})
    assert result.status_code == 200, result.text
    return {'Authorization': 'Bearer ' + result.json()['token']}


def test_public_feed_has_real_shape_and_no_members():
    result = TestClient(api.app).get('/api/v1/mobile/lr/feed')
    assert result.status_code == 200
    body = result.json()
    assert body['news'][0]['title'] == 'News & rides'
    assert body['news'][0]['body'] == 'First\n\nSecond'
    assert 'members' not in body
    assert body['chapter']['features']['guardian'] is False
    assert result.headers['cache-control'] == 'no-store'


def test_single_use_activation_hashes_secrets_and_returns_only_self():
    code, _, member = invite()
    client = TestClient(api.app)
    auth = activate(client, code)
    profile = client.get('/api/v1/mobile/lr/me', headers=auth).json()
    assert profile['id'] == str(member) and profile['status'] == 'active'
    assert 'email' not in profile and 'token_hash' not in profile
    assert client.post('/api/v1/mobile/lr/activate', json={'code': code}).status_code == 401
    with psycopg.connect(TEST_DSN) as db:
        assert db.execute('SELECT token_hash FROM mobile_sessions').fetchone()[0] != auth['Authorization'][7:]
        assert db.execute('SELECT token_hash FROM mobile_invites').fetchone()[0] != code


def test_wrong_tenant_cannot_activate_or_read_or_rsvp():
    client = TestClient(api.app)
    code, _, _ = invite('other')
    assert client.post('/api/v1/mobile/lr/activate', json={'code': code}).status_code == 401
    good, _, _ = invite()
    auth = activate(client, good)
    assert client.get('/api/v1/mobile/other/me', headers=auth).status_code == 401
    assert client.put('/api/v1/mobile/other/events/cms-42/rsvp', json={'response': 'going'}, headers=auth).status_code == 401
    assert client.get('/api/v1/mobile/other/feed').status_code == 404


def test_expired_invitation_and_suspended_member_cannot_activate():
    client = TestClient(api.app)
    code, _, _ = invite()
    with psycopg.connect(TEST_DSN) as db:
        db.execute("UPDATE mobile_invites SET expires_at=now()-interval '1 second'")
    assert client.post('/api/v1/mobile/lr/activate', json={'code': code}).status_code == 401
    suspended, _, _ = invite(status='suspended')
    assert client.post('/api/v1/mobile/lr/activate', json={'code': suspended}).status_code == 401


def test_rsvp_updates_only_own_response_and_rejects_unpublished_event():
    client = TestClient(api.app)
    code, org, _ = invite()
    auth = activate(client, code)
    other, _, _ = invite()
    other_auth = activate(client, other)
    for response in ('going', 'interested', 'not_going'):
        assert client.put('/api/v1/mobile/lr/events/cms-42/rsvp', json={'response': response}, headers=auth).status_code == 200
        assert client.get('/api/v1/mobile/lr/me', headers=auth).json()['rsvps'] == {'cms-42': response}
    assert client.get('/api/v1/mobile/lr/me', headers=other_auth).json()['rsvps'] == {}
    assert client.put('/api/v1/mobile/lr/events/cms-999/rsvp', json={'response': 'going'}, headers=auth).status_code == 404
    assert client.put('/api/v1/mobile/lr/events/cms-42/rsvp', json={'response': 'admin'}, headers=auth).status_code == 422
    assert client.put('/api/v1/mobile/lr/events/cms-42/rsvp', json={'response': 'going'}).status_code == 401


def test_sign_out_expiry_and_suspension_revoke_access():
    client = TestClient(api.app)
    code, _, _ = invite()
    auth = activate(client, code)
    assert client.delete('/api/v1/mobile/lr/session', headers=auth).status_code == 204
    assert client.get('/api/v1/mobile/lr/me', headers=auth).status_code == 401
    for change in ("UPDATE mobile_sessions SET expires_at=now()-interval '1 second'", "UPDATE members SET status='suspended'"):
        code, _, _ = invite()
        auth = activate(client, code)
        with psycopg.connect(TEST_DSN) as db:
            db.execute(change)
        assert client.get('/api/v1/mobile/lr/me', headers=auth).status_code == 401


def test_invitation_recovery_revokes_previous_session():
    client = TestClient(api.app)
    code, org, member = invite()
    auth = activate(client, code)
    new_code = 'wsi_' + secrets.token_urlsafe(32)
    with psycopg.connect(TEST_DSN) as db:
        db.execute("INSERT INTO mobile_invites VALUES(%s,%s,%s,now()+interval '1 day',NULL)", (api.digest(new_code), org, member))
    new_auth = activate(client, new_code)
    assert client.get('/api/v1/mobile/lr/me', headers=auth).status_code == 401
    assert client.get('/api/v1/mobile/lr/me', headers=new_auth).status_code == 200


def test_failed_invites_are_rate_limited():
    client = TestClient(api.app)
    for _ in range(10):
        assert client.post('/api/v1/mobile/lr/activate', json={'code': 'x' * 44}).status_code == 401
    result = client.post('/api/v1/mobile/lr/activate', json={'code': 'x' * 44})
    assert result.status_code == 429 and result.headers['retry-after'] == '900'


def test_cms_tenant_mismatch_is_rejected(monkeypatch):
    monkeypatch.setattr(api, 'cms', lambda path: {'organisation': 'other', 'events': []})
    with pytest.raises(api.HTTPException) as error:
        api.published_events('lr')
    assert error.value.status_code == 503
