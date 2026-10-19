"""Event-scoped Guardians, briefing/GPX and an explicit, auditable incident log.

Nothing in this module dispatches emergency services or sends push/email/SMS.
Receipts mean an authenticated person pressed a button, never inferred delivery.
"""
import math
from datetime import datetime, timedelta, timezone
from uuid import UUID, uuid4
from xml.etree import ElementTree as ET

from fastapi import Depends, HTTPException, Response
from pydantic import BaseModel, Field, field_validator
from psycopg.types.json import Jsonb


def text_value(value):
    value = value.strip()
    if any(ord(c) < 32 and c not in '\n\t' for c in value):
        raise ValueError('Remove control characters')
    return value


class Stop(BaseModel):
    id: UUID = Field(default_factory=uuid4)
    name: str = Field(min_length=1, max_length=150)
    kind: str = Field(pattern=r'^(meeting|fuel|coffee|rest|finish)$')
    note: str = Field(default='', max_length=500)
    latitude: float | None = Field(default=None, ge=-90, le=90, allow_inf_nan=False)
    longitude: float | None = Field(default=None, ge=-180, le=180, allow_inf_nan=False)

    @field_validator('name', 'note')
    @classmethod
    def clean(cls, value):
        return text_value(value)


class PlanBody(BaseModel):
    revision: int = Field(ge=0)
    briefing: str = Field(max_length=6000)
    meeting_point: str = Field(max_length=250)
    check_in_minutes: int = Field(ge=5, le=120)
    stops: list[Stop] = Field(max_length=20)

    @field_validator('briefing', 'meeting_point')
    @classmethod
    def clean(cls, value):
        return text_value(value)


class RouteBody(BaseModel):
    revision: int = Field(ge=0)
    gpx: str = Field(max_length=262144)


class NominationBody(BaseModel):
    member_id: UUID
    slot: str = Field(pattern=r'^(lead|sweep|deputy|responder)$')


class AcceptBody(BaseModel):
    accept: bool


class IncidentBody(BaseModel):
    client_id: UUID
    kind: str = Field(pattern=r'^(help|sos|check_in)$')
    note: str = Field(default='', max_length=1000)
    reported_at: datetime
    subject_id: UUID | None = None

    @field_validator('note')
    @classmethod
    def clean(cls, value):
        return text_value(value)

    @field_validator('reported_at')
    @classmethod
    def aware(cls, value):
        if value.tzinfo is None:
            raise ValueError('Include the time zone')
        return value


class IncidentAction(BaseModel):
    action: str = Field(pattern=r'^(acknowledged|responding|resolve|reopen)$')
    note: str = Field(default='', max_length=1000)

    @field_validator('note')
    @classmethod
    def clean(cls, value):
        return text_value(value)


class EscalationBody(BaseModel):
    note: str = Field(min_length=10, max_length=1000)

    @field_validator('note')
    @classmethod
    def clean(cls, value):
        value = text_value(value)
        if len(value) < 10:
            raise ValueError('Describe the follow-up action')
        return value


def parse_gpx(raw):
    """Import only finite route geometry. Never import author/contact/track times."""
    if len(raw.encode('utf-8')) > 262144 or '<!doctype' in raw.lower() or '<!entity' in raw.lower():
        raise HTTPException(422, 'Use a GPX file up to 256 KiB without document declarations.')
    try:
        root = ET.fromstring(raw)
        local = lambda tag: tag.rsplit('}', 1)[-1]
        if local(root.tag) != 'gpx':
            raise ValueError()
        segments = []
        total = 0
        # Preserve segment boundaries: disconnected tracks are never joined by a line.
        for element in root.iter():
            if local(element.tag) not in ('trkseg', 'rte'):
                continue
            points = []
            for node in element:
                if local(node.tag) not in ('trkpt', 'rtept'):
                    continue
                lat, lon = float(node.attrib['lat']), float(node.attrib['lon'])
                if not (math.isfinite(lat) and math.isfinite(lon) and -90 <= lat <= 90 and -180 <= lon <= 180):
                    raise ValueError()
                points.append({'latitude': lat, 'longitude': lon})
                total += 1
                if total > 4000:
                    raise ValueError()
            if len(points) >= 2:
                segments.append(points)
        if not segments or len(segments) > 100:
            raise ValueError()
        name = next((text_value(e.text or '')[:150] for e in root.iter() if local(e.tag) == 'name' and e.text), 'Chapter ride route')
        return name, segments
    except (ET.ParseError, ValueError, KeyError, TypeError):
        raise HTTPException(422, 'Use a GPX route or track with 2–4,000 valid points and at most 100 segments.')


def ride_lock(db, org, event):
    # Serialise closure, joins, handovers and incident changes for the same ride.
    db.execute('SELECT pg_advisory_xact_lock(hashtextextended(%s,0))', (str(org) + ':' + event,))


def activity(db, member, event, action, note='', incident=None):
    db.execute('INSERT INTO ride_activity(organisation_id,event_id,actor_id,incident_id,action,note) VALUES(%s,%s,%s,%s,%s,%s)',
               (member['organisation_id'], event, member['id'], incident, action, note))


def record_join(db, member, event, expires):
    org = member['organisation_id']
    ride_lock(db, org, event)
    if db.execute('SELECT 1 FROM ride_plans WHERE organisation_id=%s AND event_id=%s AND closed_at IS NOT NULL', (org, event)).fetchone():
        raise HTTPException(409, 'This ride has been closed by its Guardians.')
    # Switching rides is explicit departure, never a safe-home receipt.
    db.execute("UPDATE ride_participation SET state='left',completed_at=now() WHERE organisation_id=%s AND member_id=%s AND state='riding' AND event_id<>%s", (org, member['id'], event))
    db.execute("""INSERT INTO ride_participation(organisation_id,event_id,member_id,expires_at)
      VALUES(%s,%s,%s,%s) ON CONFLICT(organisation_id,event_id,member_id) DO UPDATE SET
      joined_at=now(),expires_at=EXCLUDED.expires_at,state='riding',checked_in_at=now(),completed_at=NULL""", (org, event, member['id'], expires))
    activity(db, member, event, 'ride.joined')


def record_end(db, member, event, state):
    ride_lock(db, member['organisation_id'], event)
    row = db.execute("""UPDATE ride_participation SET state=%s,checked_in_at=now(),completed_at=now()
      WHERE organisation_id=%s AND event_id=%s AND member_id=%s AND state IN('riding','assisted') RETURNING member_id""",
                     (state, member['organisation_id'], event, member['id'])).fetchone()
    if row:
        activity(db, member, event, 'ride.' + state)


def install_ride_operations(app, connect, identity, published_ride, lock_identity, active_rider):
    prefix = '/api/v1/mobile/{slug}/rides/{event_id}'

    def can_manage(db, member, event):
        return db.execute("""SELECT 1 FROM role_grants WHERE organisation_id=%s AND member_id=%s
          AND capability='event.manage' AND scope_type='organisation' AND scope_id IS NULL
          UNION ALL SELECT 1 FROM ride_managers WHERE organisation_id=%s AND member_id=%s AND event_id=%s LIMIT 1""",
                          (member['organisation_id'], member['id'], member['organisation_id'], member['id'], event)).fetchone() is not None

    def role(db, member, event):
        row = db.execute("""SELECT a.slot FROM ride_assignments a JOIN mobile_rsvps v
          ON v.organisation_id=a.organisation_id AND v.event_id=a.event_id AND v.member_id=a.member_id
          WHERE a.organisation_id=%s AND a.event_id=%s AND a.member_id=%s AND a.state='accepted' AND v.response='going'""",
                         (member['organisation_id'], event, member['id'])).fetchone()
        return row['slot'] if row else None

    def guardian(db, member, event):
        return role(db, member, event) in ('lead', 'sweep', 'responder')

    def permitted(db, member, event):
        return can_manage(db, member, event) or db.execute("""SELECT 1 FROM mobile_rsvps WHERE
          organisation_id=%s AND event_id=%s AND member_id=%s AND response IN('going','interested')""",
                    (member['organisation_id'], event, member['id'])).fetchone() is not None

    def get_plan(db, member, event):
        db.execute('INSERT INTO ride_plans(organisation_id,event_id) VALUES(%s,%s) ON CONFLICT DO NOTHING', (member['organisation_id'], event))
        return db.execute('SELECT * FROM ride_plans WHERE organisation_id=%s AND event_id=%s', (member['organisation_id'], event)).fetchone()

    def edit_plan(db, member, event, revision):
        lock_identity(db, member)
        ride_lock(db, member['organisation_id'], event)
        if not (can_manage(db, member, event) or role(db, member, event) == 'lead'):
            raise HTTPException(403, 'The ride organiser or accepted Road Captain can edit this briefing.')
        plan = get_plan(db, member, event)
        if plan['closed_at']:
            raise HTTPException(409, 'This ride is closed.')
        if plan['revision'] != revision:
            raise HTTPException(409, 'The briefing has changed. Refresh it before saving your edits.')
        return plan

    def roster(db, member, event):
        return db.execute("""SELECT p.*,m.display_name,m.status FROM ride_participation p JOIN members m
          ON m.organisation_id=p.organisation_id AND m.id=p.member_id WHERE p.organisation_id=%s AND p.event_id=%s
          ORDER BY p.joined_at,m.id""", (member['organisation_id'], event)).fetchall()

    def serial_incident(db, member, row):
        check_in = db.execute('SELECT checked_in_at FROM ride_participation WHERE organisation_id=%s AND event_id=%s AND member_id=%s AND checked_in_at>=%s', (row['organisation_id'], row['event_id'], row['subject_id'], row['created_at'])).fetchone()
        receipts = db.execute("""SELECT r.*,m.display_name FROM ride_incident_receipts r JOIN members m
          ON m.organisation_id=r.organisation_id AND m.id=r.member_id
          WHERE r.organisation_id=%s AND r.incident_id=%s ORDER BY r.updated_at,m.id""", (row['organisation_id'], row['id'])).fetchall()
        log = db.execute("""SELECT a.*,m.display_name FROM ride_activity a LEFT JOIN members m
          ON m.organisation_id=a.organisation_id AND m.id=a.actor_id WHERE a.organisation_id=%s
          AND a.incident_id=%s ORDER BY a.id""", (row['organisation_id'], row['id'])).fetchall()
        return {'id': str(row['id']), 'client_id': str(row['client_id']), 'event_id': row['event_id'], 'reporter_id': str(row['reporter_id']),
                'subject_id': str(row['subject_id']), 'kind': row['kind'], 'note': row['note'],
                'reported_at': row['reported_at'], 'created_at': row['created_at'],
                'resolved_at': row['resolved_at'], 'resolution': row['resolution'],
                'subject_checked_in_at': check_in['checked_in_at'] if check_in else None,
                'receipts': [{'member_id': str(r['member_id']), 'display_name': r['display_name'], 'state': r['state'], 'updated_at': r['updated_at']} for r in receipts],
                'activity': [{'id': r['id'], 'actor_name': r['display_name'] or 'Former member', 'action': r['action'], 'note': r['note'], 'created_at': r['created_at']} for r in log]}

    @app.get('/api/v1/mobile/{slug}/ride-duty')
    def duty(slug: str, member=Depends(identity)):
        with connect() as db:
            rows = db.execute("""SELECT DISTINCT a.event_id FROM ride_assignments a JOIN mobile_rsvps v
              ON v.organisation_id=a.organisation_id AND v.member_id=a.member_id AND v.event_id=a.event_id
              LEFT JOIN ride_plans p ON p.organisation_id=a.organisation_id AND p.event_id=a.event_id
              WHERE a.organisation_id=%s AND a.member_id=%s AND a.state IN('pending','accepted')
              AND v.response='going' AND p.closed_at IS NULL ORDER BY a.event_id LIMIT 50""", (member['organisation_id'], member['id'])).fetchall()
            events = [r['event_id'] for r in rows]
            # A minimal in-app badge. Content/locations still require their own checks.
            alerts = db.execute("""SELECT i.id,i.event_id,i.kind FROM ride_incidents i WHERE i.organisation_id=%s
              AND i.resolved_at IS NULL AND (i.reporter_id=%s OR i.subject_id=%s OR EXISTS(
                SELECT 1 FROM ride_assignments a JOIN mobile_rsvps v ON v.organisation_id=a.organisation_id
                AND v.member_id=a.member_id AND v.event_id=a.event_id WHERE a.organisation_id=i.organisation_id
                AND a.event_id=i.event_id AND a.member_id=%s AND a.state='accepted' AND a.slot IN('lead','sweep','responder')
                AND v.response='going')) ORDER BY CASE WHEN i.kind='sos' THEN 0 ELSE 1 END,i.created_at DESC LIMIT 50""",
                                (member['organisation_id'], member['id'], member['id'], member['id'])).fetchall()
        return {'events': events, 'alerts': [{'id': str(r['id']), 'event_id': r['event_id'], 'kind': r['kind']} for r in alerts]}

    @app.get(prefix + '/operations')
    def operations(slug: str, event_id: str, member=Depends(identity)):
        published_ride(slug, event_id)
        with connect() as db:
            if not permitted(db, member, event_id):
                raise HTTPException(403, 'RSVP Going or Interested to see the ride briefing.')
            plan = get_plan(db, member, event_id)
            manages = can_manage(db, member, event_id)
            own_role = role(db, member, event_id)
            responds = guardian(db, member, event_id)
            assignments = db.execute("""SELECT a.*,m.display_name,m.status,v.response FROM ride_assignments a JOIN members m
              ON m.organisation_id=a.organisation_id AND m.id=a.member_id LEFT JOIN mobile_rsvps v
              ON v.organisation_id=a.organisation_id AND v.member_id=a.member_id AND v.event_id=a.event_id
              WHERE a.organisation_id=%s AND a.event_id=%s AND a.state IN('pending','accepted') ORDER BY a.slot,a.nominated_at""", (member['organisation_id'], event_id)).fetchall()
            incidents = db.execute("""SELECT * FROM ride_incidents WHERE organisation_id=%s AND event_id=%s
              AND (%s OR reporter_id=%s OR subject_id=%s) ORDER BY (resolved_at IS NOT NULL),created_at DESC LIMIT 100""",
                                   (member['organisation_id'], event_id, responds, member['id'], member['id'])).fetchall()
            participants = roster(db, member, event_id) if responds else []
            candidates = db.execute("""SELECT m.id,m.display_name FROM members m JOIN mobile_rsvps v
              ON v.organisation_id=m.organisation_id AND v.member_id=m.id WHERE m.organisation_id=%s
              AND v.event_id=%s AND v.response='going' AND m.status='active' ORDER BY lower(m.display_name),m.id""", (member['organisation_id'], event_id)).fetchall() if manages else []
            recent = db.execute("""SELECT a.*,m.display_name FROM ride_activity a LEFT JOIN members m
              ON m.organisation_id=a.organisation_id AND m.id=a.actor_id WHERE a.organisation_id=%s AND a.event_id=%s
              AND a.incident_id IS NULL ORDER BY a.id DESC LIMIT 100""", (member['organisation_id'], event_id)).fetchall() if responds or manages else []
            now = datetime.now(timezone.utc)
            return {'event_id': event_id, 'revision': plan['revision'], 'briefing': plan['briefing'], 'meeting_point': plan['meeting_point'],
                    'check_in_minutes': plan['check_in_minutes'], 'stops': plan['stops'], 'route_name': plan['route_name'], 'route': plan['route'],
                    'closed_at': plan['closed_at'], 'updated_at': plan['updated_at'], 'server_time': now,
                    'can_manage': manages, 'can_edit': manages or own_role == 'lead', 'can_respond': responds, 'own_role': own_role,
                    'assignments': [{'id': str(r['id']), 'member_id': str(r['member_id']), 'display_name': r['display_name'],
                                     'slot': r['slot'], 'state': r['state'], 'available': r['status'] == 'active' and r['response'] == 'going',
                                     'accepted_at': r['accepted_at']} for r in assignments],
                    'candidates': [{'id': str(r['id']), 'display_name': r['display_name']} for r in candidates],
                    'roster': [{'id': str(r['member_id']), 'display_name': r['display_name'], 'state': r['state'],
                                'checked_in_at': r['checked_in_at'], 'expires_at': r['expires_at'], 'completed_at': r['completed_at'],
                                'needs_check_in': r['state'] == 'riding' and (now-r['checked_in_at']).total_seconds() > plan['check_in_minutes']*60,
                                'session_expired': r['state'] == 'riding' and r['expires_at'] <= now} for r in participants],
                    'incidents': [serial_incident(db, member, r) for r in incidents],
                    'activity': [{'id': r['id'], 'actor_name': r['display_name'] or 'Former member', 'action': r['action'], 'note': r['note'], 'created_at': r['created_at']} for r in recent]}

    @app.put(prefix + '/briefing', status_code=204)
    def briefing(slug: str, event_id: str, body: PlanBody, member=Depends(identity)):
        published_ride(slug, event_id)
        for stop in body.stops:
            if (stop.latitude is None) != (stop.longitude is None) or not stop.name:
                raise HTTPException(422, 'A stop needs a name and either both coordinates or neither.')
        if len({s.id for s in body.stops}) != len(body.stops):
            raise HTTPException(422, 'Each stop needs a different identifier.')
        with connect() as db:
            edit_plan(db, member, event_id, body.revision)
            db.execute("""UPDATE ride_plans SET briefing=%s,meeting_point=%s,check_in_minutes=%s,stops=%s,
              revision=revision+1,updated_at=now() WHERE organisation_id=%s AND event_id=%s""",
                       (body.briefing, body.meeting_point, body.check_in_minutes, Jsonb([s.model_dump(mode='json') for s in body.stops]), member['organisation_id'], event_id))
            activity(db, member, event_id, 'briefing.updated')
        return Response(status_code=204)

    @app.put(prefix + '/route', status_code=204)
    def route(slug: str, event_id: str, body: RouteBody, member=Depends(identity)):
        published_ride(slug, event_id)
        # Check authority before spending CPU parsing a file from a member.
        with connect() as db:
            edit_plan(db, member, event_id, body.revision)
            name, segments = parse_gpx(body.gpx) if body.gpx.strip() else ('', [])
            db.execute('UPDATE ride_plans SET route=%s,route_name=%s,revision=revision+1,updated_at=now() WHERE organisation_id=%s AND event_id=%s', (Jsonb(segments), name, member['organisation_id'], event_id))
            activity(db, member, event_id, 'route.updated')
        return Response(status_code=204)

    @app.post(prefix + '/assignments')
    def nominate(slug: str, event_id: str, body: NominationBody, member=Depends(identity)):
        published_ride(slug, event_id)
        with connect() as db:
            lock_identity(db, member)
            ride_lock(db, member['organisation_id'], event_id)
            if not can_manage(db, member, event_id):
                raise HTTPException(403, 'Only a delegated ride organiser can nominate Guardians.')
            if get_plan(db, member, event_id)['closed_at']:
                raise HTTPException(409, 'This ride is closed.')
            target = db.execute("""SELECT m.id,m.display_name FROM members m JOIN mobile_rsvps v ON v.organisation_id=m.organisation_id AND v.member_id=m.id
              WHERE m.organisation_id=%s AND m.id=%s AND m.status='active' AND v.event_id=%s AND v.response='going'""", (member['organisation_id'], body.member_id, event_id)).fetchone()
            if not target:
                raise HTTPException(404, 'Choose an active member who is Going on this ride.')
            existing = db.execute("""SELECT slot,state FROM ride_assignments WHERE organisation_id=%s AND event_id=%s AND member_id=%s
              AND state IN('pending','accepted')""", (member['organisation_id'], event_id, body.member_id)).fetchall()
            if any(r['slot'] == body.slot or r['state'] == 'pending' or r['slot'] != 'deputy' for r in existing):
                raise HTTPException(409, 'One rider cannot occupy both ends of the ride. Choose a different member.')
            # The current Guardian keeps their role until the replacement accepts.
            db.execute("UPDATE ride_assignments SET state='withdrawn' WHERE organisation_id=%s AND event_id=%s AND slot=%s AND state='pending'", (member['organisation_id'], event_id, body.slot))
            row = db.execute('INSERT INTO ride_assignments(organisation_id,event_id,slot,member_id,nominated_by) VALUES(%s,%s,%s,%s,%s) RETURNING id', (member['organisation_id'], event_id, body.slot, body.member_id, member['id'])).fetchone()
            labels = {'lead': 'Road Captain', 'sweep': 'Sweep', 'deputy': 'Deputy Guardian', 'responder': 'Designated responder'}
            activity(db, member, event_id, 'role.nominated', labels[body.slot] + ' offered to ' + target['display_name'])
        return {'id': str(row['id'])}

    @app.put(prefix + '/assignments/{assignment_id}', status_code=204)
    def accept(slug: str, event_id: str, assignment_id: UUID, body: AcceptBody, member=Depends(identity)):
        with connect() as db:
            lock_identity(db, member)
            ride_lock(db, member['organisation_id'], event_id)
            row = db.execute("SELECT * FROM ride_assignments WHERE organisation_id=%s AND event_id=%s AND id=%s AND member_id=%s AND state='pending'", (member['organisation_id'], event_id, assignment_id, member['id'])).fetchone()
            if not row:
                raise HTTPException(404, 'This invitation is no longer pending for you.')
            if get_plan(db, member, event_id)['closed_at']:
                raise HTTPException(409, 'This ride is closed.')
            if body.accept:
                if not db.execute("SELECT 1 FROM mobile_rsvps WHERE organisation_id=%s AND event_id=%s AND member_id=%s AND response='going'", (member['organisation_id'], event_id, member['id'])).fetchone():
                    raise HTTPException(403, 'RSVP Going before accepting this road role.')
                db.execute("UPDATE ride_assignments SET state='replaced' WHERE organisation_id=%s AND event_id=%s AND state='accepted' AND (slot=%s OR member_id=%s)", (member['organisation_id'], event_id, row['slot'], member['id']))
            db.execute("UPDATE ride_assignments SET state=%s,accepted_at=CASE WHEN %s THEN now() ELSE NULL END WHERE id=%s", ('accepted' if body.accept else 'declined', body.accept, row['id']))
            labels = {'lead': 'Road Captain', 'sweep': 'Sweep', 'deputy': 'Deputy Guardian', 'responder': 'Designated responder'}
            activity(db, member, event_id, 'role.accepted' if body.accept else 'role.declined', labels[row['slot']])
        return Response(status_code=204)

    @app.post(prefix + '/incidents')
    def report(slug: str, event_id: str, body: IncidentBody, member=Depends(identity)):
        with connect() as db:
            lock_identity(db, member)
            ride_lock(db, member['organisation_id'], event_id)
            previous = db.execute('SELECT * FROM ride_incidents WHERE organisation_id=%s AND reporter_id=%s AND client_id=%s', (member['organisation_id'], member['id'], body.client_id)).fetchone()
            if previous:
                if previous['event_id'] != event_id:
                    raise HTTPException(409, 'This request identifier belongs to another ride.')
                return serial_incident(db, member, previous)
            if not -30 <= (datetime.now(timezone.utc)-body.reported_at).total_seconds() <= 900:
                raise HTTPException(422, 'This unsent request is over 15 minutes old. Check the situation and send a fresh request.')
            subject = body.subject_id or member['id']
            if body.kind == 'check_in':
                if not guardian(db, member, event_id):
                    raise HTTPException(403, 'Only an accepted Guardian can request another rider’s check-in.')
                if not db.execute('SELECT 1 FROM ride_participation WHERE organisation_id=%s AND event_id=%s AND member_id=%s', (member['organisation_id'], event_id, subject)).fetchone():
                    raise HTTPException(404, 'Rider not found.')
            else:
                active_rider(db, member, event_id)
                if subject != member['id']:
                    raise HTTPException(403, 'A help request must be for yourself. Guardians can request a check-in.')
            recent = db.execute("SELECT count(*) AS n FROM ride_incidents WHERE organisation_id=%s AND reporter_id=%s AND created_at>now()-interval '1 minute'", (member['organisation_id'], member['id'])).fetchone()['n']
            if recent >= 6:
                raise HTTPException(429, 'Your requests are recorded. Wait a moment before sending another.')
            row = db.execute('INSERT INTO ride_incidents(organisation_id,event_id,reporter_id,subject_id,client_id,kind,note,reported_at) VALUES(%s,%s,%s,%s,%s,%s,%s,%s) RETURNING *', (member['organisation_id'], event_id, member['id'], subject, body.client_id, body.kind, body.note, body.reported_at)).fetchone()
            activity(db, member, event_id, 'incident.' + body.kind, body.note, row['id'])
            return serial_incident(db, member, row)

    @app.post(prefix + '/assignments/{assignment_id}/withdraw', status_code=204)
    def withdraw(slug: str, event_id: str, assignment_id: UUID, body: EscalationBody, member=Depends(identity)):
        with connect() as db:
            lock_identity(db, member)
            ride_lock(db, member['organisation_id'], event_id)
            row = db.execute("UPDATE ride_assignments SET state='withdrawn' WHERE organisation_id=%s AND event_id=%s AND id=%s AND member_id=%s AND state='accepted' RETURNING slot", (member['organisation_id'], event_id, assignment_id, member['id'])).fetchone()
            if not row:
                raise HTTPException(404, 'Your accepted road role was not found.')
            activity(db, member, event_id, 'role.withdrawn', row['slot'] + ': ' + body.note)
        return Response(status_code=204)

    @app.post(prefix + '/incidents/{incident_id}/actions', status_code=204)
    def incident_action(slug: str, event_id: str, incident_id: UUID, body: IncidentAction, member=Depends(identity)):
        with connect() as db:
            lock_identity(db, member)
            ride_lock(db, member['organisation_id'], event_id)
            row = db.execute('SELECT * FROM ride_incidents WHERE organisation_id=%s AND event_id=%s AND id=%s FOR UPDATE', (member['organisation_id'], event_id, incident_id)).fetchone()
            responds = guardian(db, member, event_id)
            if not row or not (responds or row['reporter_id'] == member['id'] or row['subject_id'] == member['id']):
                raise HTTPException(404, 'Request not found.')
            if not responds and not (body.action == 'reopen' and row['reporter_id'] == member['id']):
                raise HTTPException(403, 'Only an accepted Guardian can acknowledge or resolve this request.')
            if body.action in ('resolve', 'reopen'):
                if len(body.note) < 5:
                    raise HTTPException(422, 'Record a reason of at least five characters.')
                if body.action == 'reopen' and get_plan(db, member, event_id)['closed_at']:
                    raise HTTPException(409, 'This ride is closed. Contact the chapter directly for further assistance.')
                db.execute('UPDATE ride_incidents SET resolved_at=' + ('now()' if body.action == 'resolve' else 'NULL') + ',resolution=%s WHERE id=%s', (body.note if body.action == 'resolve' else None, incident_id))
            else:
                if row['resolved_at']:
                    raise HTTPException(409, 'This request is resolved. Reopen it with a reason if needed.')
                db.execute("""INSERT INTO ride_incident_receipts(organisation_id,incident_id,member_id,state) VALUES(%s,%s,%s,%s)
                  ON CONFLICT(organisation_id,incident_id,member_id) DO UPDATE SET
                  state=CASE WHEN ride_incident_receipts.state='responding' THEN 'responding' ELSE EXCLUDED.state END,updated_at=now()""", (member['organisation_id'], incident_id, member['id'], body.action))
            activity(db, member, event_id, 'incident.' + body.action, body.note, incident_id)
        return Response(status_code=204)

    @app.post(prefix + '/escalations', status_code=204)
    def escalate(slug: str, event_id: str, body: EscalationBody, member=Depends(identity)):
        with connect() as db:
            lock_identity(db, member)
            ride_lock(db, member['organisation_id'], event_id)
            if not guardian(db, member, event_id):
                raise HTTPException(403, 'An accepted Guardian must record the follow-up.')
            activity(db, member, event_id, 'ride.escalation', body.note)
        return Response(status_code=204)

    @app.post(prefix + '/close', status_code=204)
    def close(slug: str, event_id: str, member=Depends(identity)):
        with connect() as db:
            lock_identity(db, member)
            ride_lock(db, member['organisation_id'], event_id)
            if not guardian(db, member, event_id):
                raise HTTPException(403, 'An accepted Guardian must close the ride.')
            if db.execute("SELECT 1 FROM ride_participation WHERE organisation_id=%s AND event_id=%s AND state='riding'", (member['organisation_id'], event_id)).fetchone() or db.execute('SELECT 1 FROM ride_incidents WHERE organisation_id=%s AND event_id=%s AND resolved_at IS NULL', (member['organisation_id'], event_id)).fetchone():
                raise HTTPException(409, 'Some riders or requests are unresolved. Check on them and record follow-up; they cannot be marked safe by closing the ride.')
            get_plan(db, member, event_id)
            db.execute('UPDATE ride_plans SET closed_at=COALESCE(closed_at,now()),revision=revision+1,updated_at=now() WHERE organisation_id=%s AND event_id=%s', (member['organisation_id'], event_id))
            activity(db, member, event_id, 'ride.closed')
        return Response(status_code=204)

    @app.post(prefix + '/riders/{rider_id}/assistance', status_code=204)
    def assisting(slug: str, event_id: str, rider_id: UUID, body: EscalationBody, member=Depends(identity)):
        with connect() as db:
            lock_identity(db, member)
            ride_lock(db, member['organisation_id'], event_id)
            if not guardian(db, member, event_id):
                raise HTTPException(403, 'An accepted Guardian must confirm assistance.')
            row = db.execute("UPDATE ride_participation SET state='assisted' WHERE organisation_id=%s AND event_id=%s AND member_id=%s AND state='riding' RETURNING member_id", (member['organisation_id'], event_id, rider_id)).fetchone()
            if not row:
                raise HTTPException(404, 'An unresolved rider was not found.')
            name = db.execute('SELECT display_name FROM members WHERE organisation_id=%s AND id=%s', (member['organisation_id'], rider_id)).fetchone()['display_name']
            activity(db, member, event_id, 'ride.assisted', name + ': ' + body.note)
        return Response(status_code=204)
