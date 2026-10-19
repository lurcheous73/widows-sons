"""Guardian authority, handover, independent receipts and no-false-safe checks."""
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import psycopg
import pytest
from fastapi.testclient import TestClient
import mobile_app as api
from ride_operations import parse_gpx
from test_mobile import TEST_DSN, database
from test_community import person, going, join

pytestmark = pytest.mark.skipif(not TEST_DSN, reason='A disposable PostgreSQL test database is required')
BASE = '/api/v1/mobile/lr/rides/cms-42'


def setup():
    c = TestClient(api.app)
    manager, org, manager_id = person(c, 'Organiser')
    lead, _, lead_id = person(c, 'Lead')
    sweep, _, sweep_id = person(c, 'Sweep')
    rider, _, rider_id = person(c, 'Rider')
    for auth in (manager, lead, sweep, rider):
        going(c, auth)
    with psycopg.connect(TEST_DSN) as db:
        db.execute('INSERT INTO ride_managers(organisation_id,event_id,member_id) VALUES(%s,%s,%s)', (org, 'cms-42', manager_id))
    return c, manager, lead, sweep, rider, (org, manager_id, lead_id, sweep_id, rider_id)


def nominate(c, manager, auth, member_id, slot):
    result = c.post(BASE + '/assignments', headers=manager, json={'slot': slot, 'member_id': str(member_id)})
    assert result.status_code == 200, result.text
    assignment = result.json()['id']
    assert c.put(BASE + '/assignments/' + assignment, headers=auth, json={'accept': True}).status_code == 204
    return assignment


def report(c, auth, kind='sos', **updates):
    body = {'client_id': str(uuid4()), 'kind': kind, 'note': 'QA assistance request', 'reported_at': datetime.now(timezone.utc).isoformat()}
    body.update(updates)
    return c.post(BASE + '/incidents', headers=auth, json=body)


def operations(c, auth):
    response = c.get(BASE + '/operations', headers=auth)
    assert response.status_code == 200, response.text
    return response.json()


def test_nominees_accept_and_road_role_never_implies_admin():
    c, manager, lead, sweep, rider, ids = setup()
    assert c.post(BASE + '/assignments', headers=lead, json={'slot': 'sweep', 'member_id': str(ids[3])}).status_code == 403
    pending = c.post(BASE + '/assignments', headers=manager, json={'slot': 'lead', 'member_id': str(ids[2])}).json()['id']
    assert operations(c, lead)['can_respond'] is False
    assert c.put(BASE + '/assignments/' + pending, headers=sweep, json={'accept': True}).status_code == 404
    assert c.put(BASE + '/assignments/' + pending, headers=lead, json={'accept': True}).status_code == 204
    data = operations(c, lead)
    assert data['can_respond'] and data['can_edit'] and not data['can_manage']
    assert c.post(BASE + '/assignments', headers=lead, json={'slot': 'sweep', 'member_id': str(ids[3])}).status_code == 403
    assert c.post(BASE + '/assignments', headers=manager, json={'slot': 'sweep', 'member_id': str(ids[2])}).status_code == 409


def test_handover_keeps_current_guardian_until_deputy_accepts():
    c, manager, lead, sweep, rider, ids = setup()
    nominate(c, manager, lead, ids[2], 'lead')
    nominate(c, manager, rider, ids[4], 'deputy')
    pending = c.post(BASE + '/assignments', headers=manager, json={'slot': 'lead', 'member_id': str(ids[4])}).json()['id']
    assert operations(c, lead)['can_respond']
    assert c.put(BASE + '/assignments/' + pending, headers=rider, json={'accept': True}).status_code == 204
    assert not operations(c, lead)['can_respond']
    assert operations(c, rider)['own_role'] == 'lead'
    assert any(a['action'] == 'role.accepted' for a in operations(c, rider)['activity'])


def test_nomination_requires_same_chapter_and_going_and_can_be_declined():
    c, manager, lead, sweep, rider, ids = setup()
    outsider, _, outsider_id = person(c, slug='other')
    assert c.post(BASE + '/assignments', headers=manager, json={'slot': 'sweep', 'member_id': str(outsider_id)}).status_code == 404
    c.put('/api/v1/mobile/lr/events/cms-42/rsvp', headers=sweep, json={'response': 'interested'})
    assert c.post(BASE + '/assignments', headers=manager, json={'slot': 'sweep', 'member_id': str(ids[3])}).status_code == 404
    pending = c.post(BASE + '/assignments', headers=manager, json={'slot': 'lead', 'member_id': str(ids[2])}).json()['id']
    assert c.put(BASE + '/assignments/' + pending, headers=lead, json={'accept': False}).status_code == 204
    assert not operations(c, lead)['can_respond']


def test_both_guardians_receive_sos_and_acknowledge_independently():
    c, manager, lead, sweep, rider, ids = setup()
    nominate(c, manager, lead, ids[2], 'lead')
    nominate(c, manager, sweep, ids[3], 'sweep')
    join(c, rider)
    result = report(c, rider)
    assert result.status_code == 200, result.text
    incident = result.json()['id']
    assert result.json()['receipts'] == []
    for auth in (lead, sweep):
        assert operations(c, auth)['incidents'][0]['id'] == incident
        assert c.post(BASE + f'/incidents/{incident}/actions', headers=auth, json={'action': 'acknowledged'}).status_code == 204
    data = operations(c, rider)['incidents'][0]
    assert {r['member_id'] for r in data['receipts']} == {str(ids[2]), str(ids[3])}
    assert c.post(BASE + f'/incidents/{incident}/actions', headers=sweep, json={'action': 'responding'}).status_code == 204
    assert len(operations(c, rider)['incidents'][0]['receipts']) == 2
    assert operations(c, manager)['incidents'] == []  # No automatic admin access.
    duty = c.get('/api/v1/mobile/lr/ride-duty', headers=lead).json()
    assert duty['alerts'][0]['id'] == incident


def test_other_riders_and_tenants_cannot_read_or_mutate_incidents():
    c, manager, lead, sweep, rider, ids = setup()
    nominate(c, manager, lead, ids[2], 'lead')
    join(c, rider)
    incident = report(c, rider).json()['id']
    assert operations(c, sweep)['incidents'] == []
    assert c.post(BASE + f'/incidents/{incident}/actions', headers=sweep, json={'action': 'responding'}).status_code == 404
    assert c.post(BASE + f'/incidents/{incident}/actions', headers=rider, json={'action': 'resolve', 'note': 'Pretend safe'}).status_code == 403
    other, _, _ = person(c, slug='other')
    assert c.get(BASE + '/operations', headers=other).status_code == 401
    assert c.get(BASE + '/operations').status_code == 401


def test_request_retry_is_idempotent_even_when_old_but_ids_cannot_cross_rides():
    c, _, _, _, rider, _ = setup()
    join(c, rider)
    key = str(uuid4())
    first = report(c, rider, client_id=key).json()
    retry = report(c, rider, client_id=key, note='Different retry', reported_at=(datetime.now(timezone.utc)-timedelta(hours=1)).isoformat())
    assert retry.status_code == 200 and retry.json() == first
    assert report(c, rider, reported_at=(datetime.now(timezone.utc)-timedelta(minutes=16)).isoformat()).status_code == 422
    assert report(c, rider, subject_id=str(uuid4())).status_code == 403


def test_resolve_requires_reason_is_shared_and_reporter_can_reopen():
    c, manager, lead, sweep, rider, ids = setup()
    nominate(c, manager, lead, ids[2], 'lead')
    nominate(c, manager, sweep, ids[3], 'sweep')
    join(c, rider)
    incident = report(c, rider).json()['id']
    path = BASE + f'/incidents/{incident}/actions'
    assert c.post(path, headers=lead, json={'action': 'resolve', 'note': 'ok'}).status_code == 422
    assert c.post(path, headers=lead, json={'action': 'resolve', 'note': 'Rider contacted, recovery arranged'}).status_code == 204
    assert operations(c, sweep)['incidents'][0]['resolution'] == 'Rider contacted, recovery arranged'
    assert c.post(path, headers=rider, json={'action': 'reopen', 'note': 'Still need assistance'}).status_code == 204
    assert operations(c, sweep)['incidents'][0]['resolved_at'] is None


def test_going_revocation_and_expired_sessions_remove_guardian_power():
    c, manager, lead, _, rider, ids = setup()
    nominate(c, manager, lead, ids[2], 'lead')
    c.put('/api/v1/mobile/lr/events/cms-42/rsvp', headers=lead, json={'response': 'interested'})
    assert operations(c, lead)['can_respond'] is False
    assert c.post(BASE + '/close', headers=lead).status_code == 403
    c.delete('/api/v1/mobile/lr/session', headers=lead)
    assert c.get(BASE + '/operations', headers=lead).status_code == 401


def test_briefing_optimistic_revision_stops_and_route_geometry_only():
    c, manager, lead, sweep, _, ids = setup()
    nominate(c, manager, lead, ids[2], 'lead')
    plan = {'revision': 0, 'briefing': 'Meet fuelled up. Staggered formation.', 'meeting_point': 'Chapter meeting place', 'check_in_minutes': 15,
            'stops': [{'name': 'Coffee stop', 'kind': 'coffee', 'latitude': 52.6, 'longitude': -1.1}]}
    assert c.put(BASE + '/briefing', headers=sweep, json=plan).status_code == 403
    assert c.put(BASE + '/briefing', headers=lead, json=plan).status_code == 204
    assert c.put(BASE + '/briefing', headers=manager, json=plan).status_code == 409
    gpx = '<gpx><metadata><author>PRIVATE</author></metadata><trk><name>Sunday loop</name><trkseg><trkpt lat="52.6" lon="-1.1"><time>PRIVATE</time></trkpt><trkpt lat="52.7" lon="-1.2"/></trkseg><trkseg><trkpt lat="52.8" lon="-1.3"/><trkpt lat="52.9" lon="-1.4"/></trkseg></trk></gpx>'
    assert c.put(BASE + '/route', headers=lead, json={'revision': 1, 'gpx': gpx}).status_code == 204
    data = operations(c, lead)
    assert data['revision'] == 2 and len(data['route']) == 2
    assert 'PRIVATE' not in str(data['route']) and data['route_name'] == 'Sunday loop'
    assert c.put(BASE + '/route', headers=manager, json={'revision': 1, 'gpx': ''}).status_code == 409


@pytest.mark.parametrize('gpx', ['<!DOCTYPE gpx [<!ENTITY x "xx">]><gpx/>', '<gpx><rte><rtept lat="NaN" lon="0"/><rtept lat="0" lon="0"/></rte></gpx>', '<gpx><trk><trkseg><trkpt lat="91" lon="0"/><trkpt lat="0" lon="0"/></trkseg></trk></gpx>', '<gpx/>', '<broken>'])
def test_gpx_rejects_entities_nonfinite_out_of_bounds_and_empty(gpx):
    from fastapi import HTTPException
    with pytest.raises(HTTPException):
        parse_gpx(gpx)


def test_lost_signal_is_check_in_needed_never_crashed_and_receipts_survive_lease():
    c, manager, lead, _, rider, ids = setup()
    nominate(c, manager, lead, ids[2], 'lead')
    join(c, rider)
    with psycopg.connect(TEST_DSN) as db:
        db.execute("UPDATE ride_participation SET checked_in_at=now()-interval '1 hour',expires_at=now()-interval '1 minute'")
        db.execute("UPDATE live_riders SET expires_at=now()-interval '25 hours'")
    api.app.state.community_cleanup()
    data = operations(c, lead)
    assert data['roster'][0]['needs_check_in'] and data['roster'][0]['session_expired']
    assert data['roster'][0]['state'] == 'riding' and 'crashed' not in str(data)
    assert report(c, lead, kind='check_in', subject_id=str(ids[4])).status_code == 200
    assert len(operations(c, rider)['incidents']) == 1


def test_home_removes_coordinates_and_both_guardians_keep_arrival_receipt():
    c, manager, lead, sweep, rider, ids = setup()
    nominate(c, manager, lead, ids[2], 'lead')
    nominate(c, manager, sweep, ids[3], 'sweep')
    join(c, rider)
    assert c.post(BASE + '/end', headers=rider, json={'state': 'home'}).status_code == 204
    for auth in (lead, sweep):
        row = operations(c, auth)['roster'][0]
        assert row['state'] == 'home' and row['completed_at'] is not None
        assert 'latitude' not in row and 'longitude' not in row


def test_close_refuses_unresolved_riders_and_requests_without_fake_safe_status():
    c, manager, lead, _, rider, ids = setup()
    nominate(c, manager, lead, ids[2], 'lead')
    join(c, rider)
    incident = report(c, rider).json()['id']
    assert c.post(BASE + '/close', headers=lead).status_code == 409
    assert c.post(BASE + '/escalations', headers=lead, json={'note': 'Sweep has stopped to contact the rider directly.'}).status_code == 204
    assert c.post(BASE + '/close', headers=lead).status_code == 409
    c.post(BASE + '/end', headers=rider, json={'state': 'home'})
    assert c.post(BASE + '/close', headers=lead).status_code == 409
    c.post(BASE + f'/incidents/{incident}/actions', headers=lead, json={'action': 'resolve', 'note': 'Rider confirmed safely home'})
    assert c.post(BASE + '/close', headers=lead).status_code == 204
    assert operations(c, lead)['closed_at'] is not None
    assert c.post(BASE + '/join', headers=rider, json={}).status_code == 409


def test_guardian_can_step_down_with_visible_reason_but_cannot_disable_other():
    c, manager, lead, sweep, rider, ids = setup()
    assignment = nominate(c, manager, lead, ids[2], 'lead')
    path = BASE + '/assignments/' + assignment + '/withdraw'
    assert c.post(path, headers=sweep, json={'note': 'Cannot continue this ride'}).status_code == 404
    assert c.post(path, headers=lead, json={'note': 'Cannot continue this ride'}).status_code == 204
    assert not operations(c, lead)['can_respond']
    assert any(a['action'] == 'role.withdrawn' for a in operations(c, manager)['activity'])


def test_check_in_response_is_visible_without_silently_resolving_request():
    c, manager, lead, _, rider, ids = setup()
    nominate(c, manager, lead, ids[2], 'lead')
    join(c, rider)
    incident = report(c, lead, kind='check_in', subject_id=str(ids[4])).json()
    assert incident['subject_checked_in_at'] is None
    assert c.post(BASE + '/check-in', headers=rider).status_code == 204
    updated = operations(c, lead)['incidents'][0]
    assert updated['subject_checked_in_at'] is not None and updated['resolved_at'] is None


def test_assisted_requires_guardian_and_reason_and_can_later_become_home():
    c, manager, lead, _, rider, ids = setup()
    nominate(c, manager, lead, ids[2], 'lead')
    join(c, rider)
    path = BASE + '/riders/' + str(ids[4]) + '/assistance'
    assert c.post(path, headers=manager, json={'note': 'Recovery has arrived'}).status_code == 403
    assert c.post(path, headers=lead, json={'note': 'OK'}).status_code == 422
    assert c.post(path, headers=lead, json={'note': 'Recovery truck and Sweep are with rider'}).status_code == 204
    assert operations(c, lead)['roster'][0]['state'] == 'assisted'
    assert operations(c, lead)['roster'][0]['completed_at'] is None
    c.post(BASE + '/end', headers=rider, json={'state': 'home'})
    assert operations(c, lead)['roster'][0]['state'] == 'home'


def test_read_cursor_cannot_mark_messages_from_another_room_read():
    from test_community import chapter_room, send
    c, manager, lead, _, _, ids = setup()
    chapter = chapter_room(c, lead)
    dm = c.post('/api/v1/mobile/lr/conversations/direct', headers=manager, json={'member_id': str(ids[2])}).json()['id']
    foreign = send(c, manager, dm).json()['id']
    assert c.put('/api/v1/mobile/lr/conversations/' + chapter + '/read', headers=lead, json={'message_id': foreign}).status_code == 404
