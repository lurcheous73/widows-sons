"""Private chapter messaging, explicitly joined ride tracking and voice leases.

Precise positions are a single current fix, never a route history. They are
removed on stop/home/leave and expire from responses after two minutes. All
private reads use the same active member/session checks as the mobile API.
"""
import asyncio
import json
import os
from contextlib import asynccontextmanager, suppress
from datetime import datetime, timedelta, timezone
from uuid import UUID, uuid4
from urllib.parse import parse_qs, urlsplit
from zoneinfo import ZoneInfo

import anyio
from fastapi import Depends, HTTPException, Query, Request, Response
import jwt
from livekit import api as livekit
from pydantic import BaseModel, Field, field_validator
from ride_operations import install_ride_operations, record_join, record_end


class DirectBody(BaseModel):
    member_id: UUID


class MessageBody(BaseModel):
    client_id: UUID
    body: str = Field(min_length=1, max_length=2000)

    @field_validator('body')
    @classmethod
    def trim_body(cls, value):
        value = value.strip()
        if not value or any(ord(c) < 32 and c not in '\n\t' for c in value):
            raise ValueError('Write a message without control characters')
        return value


class ReadBody(BaseModel):
    message_id: int = Field(ge=0)


class ReportBody(BaseModel):
    reason: str = Field(min_length=1, max_length=500)


class JoinBody(BaseModel):
    minutes: int = Field(default=240, ge=15, le=480)


class PositionBody(BaseModel):
    sharing_id: UUID
    latitude: float = Field(ge=-90, le=90, allow_inf_nan=False)
    longitude: float = Field(ge=-180, le=180, allow_inf_nan=False)
    accuracy: float = Field(ge=0, le=1000, allow_inf_nan=False)
    captured_at: datetime

    @field_validator('captured_at')
    @classmethod
    def aware(cls, value):
        if value.tzinfo is None:
            raise ValueError('Include the position timestamp time zone')
        return value


class EndBody(BaseModel):
    state: str = Field(pattern=r'^(home|left)$')


class VoiceBody(BaseModel):
    event_id: str | None = Field(default=None, pattern=r'^cms-[0-9]+$')


def install_community(app, connect, identity, cms, chapter):
    prefix = '/api/v1/mobile/{slug}'

    def lock_identity(db, member):
        row = db.execute("""SELECT m.status FROM members m JOIN mobile_sessions s
          ON s.member_id=m.id AND s.organisation_id=m.organisation_id
          WHERE m.organisation_id=%s AND m.id=%s AND s.token_hash=%s
          AND m.status='active' AND s.revoked_at IS NULL AND s.expires_at>now()
          FOR UPDATE OF m,s""", (member['organisation_id'], member['id'], member['token_hash'])).fetchone()
        if not row:
            raise HTTPException(401, 'Your sign-in has ended.')

    def blocked(db, org, first, second):
        return db.execute("""SELECT 1 FROM member_blocks WHERE organisation_id=%s
          AND ((member_id=%s AND blocked_id=%s) OR (member_id=%s AND blocked_id=%s))""",
                          (org, first, second, second, first)).fetchone() is not None

    def conversation(db, member, conversation_id, writing=False):
        row = db.execute('SELECT * FROM conversations WHERE organisation_id=%s AND id=%s',
                         (member['organisation_id'], conversation_id)).fetchone()
        if not row:
            raise HTTPException(404, 'Conversation not found.')
        if row['kind'] == 'direct':
            if member['id'] not in (row['first_member'], row['second_member']):
                raise HTTPException(404, 'Conversation not found.')
            other = row['second_member'] if member['id'] == row['first_member'] else row['first_member']
            if writing and (blocked(db, member['organisation_id'], member['id'], other) or not db.execute(
                    "SELECT 1 FROM members WHERE organisation_id=%s AND id=%s AND status='active'",
                    (member['organisation_id'], other)).fetchone()):
                raise HTTPException(403, 'This direct conversation cannot accept messages.')
        if row['kind'] == 'ride' and not db.execute("""SELECT 1 FROM mobile_rsvps WHERE
                organisation_id=%s AND member_id=%s AND event_id=%s AND response IN ('going','interested')""",
                (member['organisation_id'], member['id'], row['event_id'])).fetchone():
            raise HTTPException(403, 'RSVP Going or Interested to join the ride conversation.')
        return row

    def serial_message(row):
        return {'id': row['id'], 'conversation_id': str(row['conversation_id']),
                'sender_id': str(row['sender_id']), 'sender_name': row['sender_name'],
                'client_id': str(row['client_id']), 'body': row['body'] if row['deleted_at'] is None else '',
                'sent_at': row['sent_at'].isoformat(), 'deleted': row['deleted_at'] is not None}

    @app.get(prefix + '/members')
    def members(slug: str, member=Depends(identity)):
        with connect() as db:
            rows = db.execute("""SELECT m.id,m.display_name,EXISTS(SELECT 1 FROM member_blocks b
              WHERE b.organisation_id=m.organisation_id AND b.member_id=%s AND b.blocked_id=m.id) AS blocked
              FROM members m WHERE m.organisation_id=%s AND m.status='active' AND m.id<>%s
              ORDER BY lower(m.display_name),m.id LIMIT 1000""",
                              (member['id'], member['organisation_id'], member['id'])).fetchall()
        return {'members': [{'id': str(r['id']), 'display_name': r['display_name'], 'blocked': r['blocked']} for r in rows]}

    @app.put(prefix + '/members/{other_id}/block', status_code=204)
    def block(slug: str, other_id: UUID, member=Depends(identity)):
        with connect() as db:
            lock_identity(db, member)
            if other_id == member['id'] or not db.execute('SELECT 1 FROM members WHERE organisation_id=%s AND id=%s', (member['organisation_id'], other_id)).fetchone():
                raise HTTPException(404, 'Member not found.')
            db.execute('INSERT INTO member_blocks(organisation_id,member_id,blocked_id) VALUES(%s,%s,%s) ON CONFLICT DO NOTHING', (member['organisation_id'], member['id'], other_id))
        return Response(status_code=204)

    @app.delete(prefix + '/members/{other_id}/block', status_code=204)
    def unblock(slug: str, other_id: UUID, member=Depends(identity)):
        with connect() as db:
            lock_identity(db, member)
            db.execute('DELETE FROM member_blocks WHERE organisation_id=%s AND member_id=%s AND blocked_id=%s', (member['organisation_id'], member['id'], other_id))
        return Response(status_code=204)

    @app.get(prefix + '/conversations')
    def conversations(slug: str, member=Depends(identity)):
        with connect() as db:
            # Unique scope key makes concurrent first visits create one chapter room.
            db.execute("""INSERT INTO conversations(organisation_id,kind,scope_key,title)
              VALUES(%s,'chapter','chapter','Chapter clubhouse') ON CONFLICT DO NOTHING""", (member['organisation_id'],))
            rows = db.execute("""SELECT c.*, COALESCE(other.display_name,c.title) AS display_title,
              recent.body AS last_body,recent.sent_at AS last_at,recent.deleted_at AS last_deleted,
              (SELECT count(*) FROM conversation_messages x WHERE x.organisation_id=c.organisation_id
                AND x.conversation_id=c.id AND x.sender_id<>%s AND x.id>COALESCE(r.last_read_id,0)) AS unread
              FROM conversations c LEFT JOIN conversation_reads r ON r.organisation_id=c.organisation_id
                AND r.conversation_id=c.id AND r.member_id=%s
              LEFT JOIN members other ON other.organisation_id=c.organisation_id
                AND other.id=CASE WHEN c.first_member=%s THEN c.second_member ELSE c.first_member END
              LEFT JOIN LATERAL(SELECT body,sent_at,deleted_at FROM conversation_messages x WHERE
                x.organisation_id=c.organisation_id AND x.conversation_id=c.id ORDER BY id DESC LIMIT 1) recent ON true
              WHERE c.organisation_id=%s AND (c.kind='chapter' OR (c.kind='direct' AND %s IN(c.first_member,c.second_member))
                OR (c.kind='ride' AND EXISTS(SELECT 1 FROM mobile_rsvps v WHERE v.organisation_id=c.organisation_id
                  AND v.event_id=c.event_id AND v.member_id=%s AND v.response IN('going','interested'))))
              ORDER BY COALESCE(recent.sent_at,c.created_at) DESC,c.id LIMIT 200""",
                              (member['id'], member['id'], member['id'], member['organisation_id'], member['id'], member['id'])).fetchall()
        return {'conversations': [{'id': str(r['id']), 'kind': r['kind'], 'title': r['display_title'],
                'event_id': r['event_id'], 'other_member_id': str(r['second_member'] if r['first_member'] == member['id'] else r['first_member']) if r['kind'] == 'direct' else None,
                'last_message': 'Message removed' if r['last_deleted'] else (r['last_body'] or ''),
                'last_at': r['last_at'].isoformat() if r['last_at'] else None, 'unread': r['unread']} for r in rows]}

    @app.post(prefix + '/conversations/direct')
    def direct(slug: str, body: DirectBody, member=Depends(identity)):
        with connect() as db:
            lock_identity(db, member)
            if body.member_id == member['id'] or not db.execute("SELECT 1 FROM members WHERE organisation_id=%s AND id=%s AND status='active'", (member['organisation_id'], body.member_id)).fetchone():
                raise HTTPException(404, 'Member not found.')
            if blocked(db, member['organisation_id'], member['id'], body.member_id):
                raise HTTPException(403, 'This direct conversation is blocked.')
            first, second = sorted((member['id'], body.member_id))
            row = db.execute("""INSERT INTO conversations(organisation_id,kind,scope_key,title,first_member,second_member)
              VALUES(%s,'direct',%s,'Direct message',%s,%s) ON CONFLICT(organisation_id,scope_key)
              DO UPDATE SET scope_key=EXCLUDED.scope_key RETURNING id""", (member['organisation_id'], f'direct:{first}:{second}', first, second)).fetchone()
        return {'id': str(row['id'])}

    def published_ride(slug, event_id):
        chapter(slug)
        if not event_id.startswith('cms-') or not event_id[4:].isdigit():
            raise HTTPException(404, 'Ride not found.')
        # Fetch the public post itself: a ride remains usable after departure,
        # even when it has left the website's upcoming-events feed.
        post = cms('/wp-json/wp/v2/ws_event/' + event_id[4:])
        if str(post.get('id')) != event_id[4:] or post.get('status') != 'publish':
            raise HTTPException(404, 'This ride is not published.')
        raw = post.get('meta', {}).get('_ws_starts_at', '')
        try:
            start = datetime.fromisoformat(raw).replace(tzinfo=ZoneInfo('Europe/London'))
        except (ValueError, TypeError):
            raise HTTPException(409, 'This ride needs a confirmed start time.')
        return post, start

    @app.post(prefix + '/rides/{event_id}/conversation')
    def ride_conversation(slug: str, event_id: str, member=Depends(identity)):
        post, _ = published_ride(slug, event_id)
        with connect() as db:
            lock_identity(db, member)
            if not db.execute("""SELECT 1 FROM mobile_rsvps WHERE organisation_id=%s AND member_id=%s
              AND event_id=%s AND response IN('going','interested')""", (member['organisation_id'], member['id'], event_id)).fetchone():
                raise HTTPException(403, 'RSVP Going or Interested to join the ride conversation.')
            row = db.execute("""INSERT INTO conversations(organisation_id,kind,scope_key,title,event_id)
              VALUES(%s,'ride',%s,%s,%s) ON CONFLICT(organisation_id,scope_key)
              DO UPDATE SET title=EXCLUDED.title RETURNING id""", (member['organisation_id'], 'ride:' + event_id, 'Ride conversation', event_id)).fetchone()
        return {'id': str(row['id'])}

    @app.get(prefix + '/conversations/{conversation_id}/messages')
    def messages(slug: str, conversation_id: UUID, before: int | None = Query(default=None, ge=1), after: int = Query(default=0, ge=0), member=Depends(identity)):
        with connect() as db:
            conversation(db, member, conversation_id)
            rows = db.execute("""SELECT x.*,m.display_name AS sender_name FROM conversation_messages x JOIN members m
              ON m.organisation_id=x.organisation_id AND m.id=x.sender_id WHERE x.organisation_id=%s
              AND x.conversation_id=%s AND x.id>%s AND (%s::bigint IS NULL OR x.id<%s)
              ORDER BY x.id DESC LIMIT 50""", (member['organisation_id'], conversation_id, after, before, before)).fetchall()
        return {'messages': [serial_message(r) for r in reversed(rows)], 'has_older': len(rows) == 50}

    @app.post(prefix + '/conversations/{conversation_id}/messages')
    def send(slug: str, conversation_id: UUID, body: MessageBody, member=Depends(identity)):
        with connect() as db:
            lock_identity(db, member)
            conversation(db, member, conversation_id, writing=True)
            previous = db.execute('SELECT conversation_id FROM conversation_messages WHERE organisation_id=%s AND sender_id=%s AND client_id=%s', (member['organisation_id'], member['id'], body.client_id)).fetchone()
            if previous and previous['conversation_id'] != conversation_id:
                raise HTTPException(409, 'This message identifier belongs to another conversation.')
            if not previous and db.execute("SELECT count(*) AS n FROM conversation_messages WHERE organisation_id=%s AND sender_id=%s AND sent_at>now()-interval '1 minute'", (member['organisation_id'], member['id'])).fetchone()['n'] >= 30:
                raise HTTPException(429, 'Please wait a moment before sending more messages.')
            row = db.execute("""INSERT INTO conversation_messages(organisation_id,conversation_id,sender_id,client_id,body)
              VALUES(%s,%s,%s,%s,%s) ON CONFLICT(organisation_id,sender_id,client_id)
              DO UPDATE SET client_id=EXCLUDED.client_id RETURNING *""", (member['organisation_id'], conversation_id, member['id'], body.client_id, body.body)).fetchone()
            row['sender_name'] = member['display_name']
        return serial_message(row)

    @app.put(prefix + '/conversations/{conversation_id}/read', status_code=204)
    def read(slug: str, conversation_id: UUID, body: ReadBody, member=Depends(identity)):
        with connect() as db:
            lock_identity(db, member)
            conversation(db, member, conversation_id)
            if body.message_id > 0 and not db.execute('SELECT 1 FROM conversation_messages WHERE organisation_id=%s AND conversation_id=%s AND id=%s', (member['organisation_id'], conversation_id, body.message_id)).fetchone():
                raise HTTPException(404, 'Message not found in this conversation.')
            maximum = db.execute('SELECT COALESCE(max(id),0) AS n FROM conversation_messages WHERE organisation_id=%s AND conversation_id=%s', (member['organisation_id'], conversation_id)).fetchone()['n']
            db.execute("""INSERT INTO conversation_reads VALUES(%s,%s,%s,%s) ON CONFLICT(organisation_id,conversation_id,member_id)
              DO UPDATE SET last_read_id=GREATEST(conversation_reads.last_read_id,EXCLUDED.last_read_id)""", (member['organisation_id'], conversation_id, member['id'], min(body.message_id, maximum)))
        return Response(status_code=204)

    @app.delete(prefix + '/conversations/{conversation_id}/messages/{message_id}', status_code=204)
    def delete_message(slug: str, conversation_id: UUID, message_id: int, member=Depends(identity)):
        with connect() as db:
            lock_identity(db, member)
            conversation(db, member, conversation_id)
            result = db.execute("""UPDATE conversation_messages SET body='',deleted_at=COALESCE(deleted_at,now())
              WHERE organisation_id=%s AND conversation_id=%s AND id=%s AND sender_id=%s RETURNING id""", (member['organisation_id'], conversation_id, message_id, member['id'])).fetchone()
            if not result:
                raise HTTPException(404, 'Your message was not found.')
        return Response(status_code=204)

    @app.post(prefix + '/conversations/{conversation_id}/messages/{message_id}/report', status_code=204)
    def report_message(slug: str, conversation_id: UUID, message_id: int, body: ReportBody, member=Depends(identity)):
        with connect() as db:
            lock_identity(db, member)
            conversation(db, member, conversation_id)
            if not db.execute('SELECT 1 FROM conversation_messages WHERE organisation_id=%s AND conversation_id=%s AND id=%s', (member['organisation_id'], conversation_id, message_id)).fetchone():
                raise HTTPException(404, 'Message not found.')
            db.execute('INSERT INTO message_reports(organisation_id,message_id,member_id,reason) VALUES(%s,%s,%s,%s) ON CONFLICT DO NOTHING', (member['organisation_id'], message_id, member['id'], body.reason.strip() or 'Reported by member'))
        return Response(status_code=204)

    def active_rider(db, member, event_id, lock=False):
        row = db.execute("""SELECT * FROM live_riders WHERE organisation_id=%s AND event_id=%s AND member_id=%s
          AND session_hash=%s AND expires_at>now() AND state='riding'
          AND EXISTS(SELECT 1 FROM mobile_rsvps v WHERE v.organisation_id=live_riders.organisation_id
            AND v.event_id=live_riders.event_id AND v.member_id=live_riders.member_id AND v.response='going')""" + (' FOR UPDATE' if lock else ''),
                         (member['organisation_id'], event_id, member['id'], member['token_hash'])).fetchone()
        if not row:
            raise HTTPException(403, 'Join this live ride first. Ride sharing may have expired.')
        return row

    @app.post(prefix + '/rides/{event_id}/join')
    def join(slug: str, event_id: str, body: JoinBody, member=Depends(identity)):
        _, start = published_ride(slug, event_id)
        now = datetime.now(timezone.utc)
        if not start - timedelta(hours=12) <= now <= start + timedelta(hours=48):
            raise HTTPException(409, 'Live ride mode opens 12 hours before departure and closes 48 hours afterwards.')
        expires = min(now + timedelta(minutes=body.minutes), member['expires_at'], start + timedelta(hours=48))
        with connect() as db:
            lock_identity(db, member)
            if not db.execute("""SELECT 1 FROM mobile_rsvps WHERE organisation_id=%s AND member_id=%s
              AND event_id=%s AND response='going'""", (member['organisation_id'], member['id'], event_id)).fetchone():
                raise HTTPException(403, 'RSVP Going before joining the live ride.')
            record_join(db, member, event_id, expires)
            db.execute("""UPDATE live_riders SET state='left',sharing=false,sharing_id=NULL,latitude=NULL,longitude=NULL,accuracy=NULL,captured_at=NULL,received_at=NULL
              WHERE organisation_id=%s AND member_id=%s AND state='riding'""", (member['organisation_id'], member['id']))
            db.execute("""INSERT INTO live_riders(organisation_id,event_id,member_id,session_hash,expires_at)
              VALUES(%s,%s,%s,%s,%s) ON CONFLICT(organisation_id,event_id,member_id) DO UPDATE SET
              session_hash=EXCLUDED.session_hash,joined_at=now(),expires_at=EXCLUDED.expires_at,state='riding',
              sharing=false,sharing_id=NULL,latitude=NULL,longitude=NULL,accuracy=NULL,captured_at=NULL,received_at=NULL,checked_in_at=now()""",
                       (member['organisation_id'], event_id, member['id'], member['token_hash'], expires))
        return {'event_id': event_id, 'expires_at': expires.isoformat()}

    @app.get(prefix + '/rides/{event_id}/live')
    def ride_state(slug: str, event_id: str, member=Depends(identity)):
        with connect() as db:
            own = active_rider(db, member, event_id)
            rows = db.execute("""SELECT r.*,m.display_name FROM live_riders r JOIN members m ON
              m.organisation_id=r.organisation_id AND m.id=r.member_id JOIN mobile_sessions s ON s.token_hash=r.session_hash
              WHERE r.organisation_id=%s AND r.event_id=%s AND r.expires_at>now() AND m.status='active'
              AND s.revoked_at IS NULL AND s.expires_at>now() ORDER BY lower(m.display_name),m.id""", (member['organisation_id'], event_id)).fetchall()
        now = datetime.now(timezone.utc)
        riders = []
        for row in rows:
            visible = row['state'] == 'riding' and row['sharing'] and row['received_at'] and row['captured_at'] and (now - row['received_at']).total_seconds() < 120 and (now - row['captured_at']).total_seconds() < 120
            riders.append({'id': str(row['member_id']), 'display_name': row['display_name'], 'state': row['state'],
                           'sharing': row['sharing'], 'latitude': row['latitude'] if visible else None,
                           'longitude': row['longitude'] if visible else None, 'accuracy': row['accuracy'] if visible else None,
                           'captured_at': row['captured_at'].isoformat() if visible and row['captured_at'] else None,
                           'received_at': row['received_at'].isoformat() if visible else None,
                           'checked_in_at': row['checked_in_at'].isoformat()})
        return {'event_id': event_id, 'expires_at': own['expires_at'].isoformat(), 'riders': riders, 'server_time': now.isoformat()}

    @app.post(prefix + '/rides/{event_id}/sharing')
    def start_sharing(slug: str, event_id: str, member=Depends(identity)):
        sharing_id = uuid4()
        with connect() as db:
            lock_identity(db, member)
            active_rider(db, member, event_id, lock=True)
            db.execute("""UPDATE live_riders SET sharing=true,sharing_id=%s,latitude=NULL,longitude=NULL,accuracy=NULL,
              captured_at=NULL,received_at=NULL WHERE organisation_id=%s AND event_id=%s AND member_id=%s""", (sharing_id, member['organisation_id'], event_id, member['id']))
        return {'sharing_id': str(sharing_id)}

    @app.put(prefix + '/rides/{event_id}/position', status_code=204)
    def position(slug: str, event_id: str, body: PositionBody, member=Depends(identity)):
        now = datetime.now(timezone.utc)
        age = (now - body.captured_at).total_seconds()
        if not -30 <= age <= 120:
            raise HTTPException(422, 'Use a recent location fix with a correct timestamp.')
        with connect() as db:
            lock_identity(db, member)
            own = active_rider(db, member, event_id, lock=True)
            if not own['sharing'] or own['sharing_id'] != body.sharing_id:
                raise HTTPException(409, 'Position sharing has stopped. Enable sharing again to send a new position.')
            if own['captured_at'] and body.captured_at <= own['captured_at']:
                raise HTTPException(409, 'A newer position has already been received.')
            db.execute("""UPDATE live_riders SET sharing=true,latitude=%s,longitude=%s,accuracy=%s,captured_at=%s,
              received_at=now(),checked_in_at=now() WHERE organisation_id=%s AND event_id=%s AND member_id=%s""",
                       (body.latitude, body.longitude, body.accuracy, body.captured_at, member['organisation_id'], event_id, member['id']))
        return Response(status_code=204)

    @app.delete(prefix + '/rides/{event_id}/position', status_code=204)
    def stop_position(slug: str, event_id: str, member=Depends(identity)):
        with connect() as db:
            lock_identity(db, member)
            db.execute("""UPDATE live_riders SET sharing=false,sharing_id=NULL,latitude=NULL,longitude=NULL,accuracy=NULL,captured_at=NULL,received_at=NULL
              WHERE organisation_id=%s AND event_id=%s AND member_id=%s""", (member['organisation_id'], event_id, member['id']))
        return Response(status_code=204)

    @app.post(prefix + '/rides/{event_id}/check-in', status_code=204)
    def check_in(slug: str, event_id: str, member=Depends(identity)):
        with connect() as db:
            lock_identity(db, member)
            active_rider(db, member, event_id)
            db.execute('UPDATE live_riders SET checked_in_at=now() WHERE organisation_id=%s AND event_id=%s AND member_id=%s', (member['organisation_id'], event_id, member['id']))
            db.execute('UPDATE ride_participation SET checked_in_at=now() WHERE organisation_id=%s AND event_id=%s AND member_id=%s', (member['organisation_id'], event_id, member['id']))
        return Response(status_code=204)

    @app.post(prefix + '/rides/{event_id}/end', status_code=204)
    def end(slug: str, event_id: str, body: EndBody, member=Depends(identity)):
        with connect() as db:
            lock_identity(db, member)
            record_end(db, member, event_id, body.state)
            db.execute("""UPDATE live_riders SET state=%s,sharing=false,sharing_id=NULL,latitude=NULL,longitude=NULL,accuracy=NULL,
              captured_at=NULL,received_at=NULL,checked_in_at=now() WHERE organisation_id=%s AND event_id=%s AND member_id=%s""", (body.state, member['organisation_id'], event_id, member['id']))
            db.execute('UPDATE voice_grants SET revoked_at=now() WHERE organisation_id=%s AND member_id=%s AND event_id=%s AND revoked_at IS NULL', (member['organisation_id'], member['id'], event_id))
        return Response(status_code=204)

    install_ride_operations(app, connect, identity, published_ride, lock_identity, active_rider)

    def voice_config():
        key, secret = os.environ.get('WIDOWS_SONS_VOICE_KEY'), os.environ.get('WIDOWS_SONS_VOICE_SECRET')
        if not key or not secret:
            raise HTTPException(503, 'The chapter intercom is not configured yet.')
        return key, secret

    def active_voice_identity(room, participant):
        with connect() as db:
            return db.execute("""SELECT v.id FROM voice_grants v JOIN mobile_sessions s ON s.token_hash=v.session_hash
              JOIN members m ON m.organisation_id=v.organisation_id AND m.id=v.member_id
              WHERE v.participant_identity=%s AND v.room_name=%s AND v.revoked_at IS NULL AND v.expires_at>now()
              AND s.revoked_at IS NULL AND s.expires_at>now() AND m.status='active'
              AND (v.event_id IS NULL OR EXISTS(SELECT 1 FROM live_riders r JOIN mobile_rsvps p
                ON p.organisation_id=r.organisation_id AND p.member_id=r.member_id AND p.event_id=r.event_id
                WHERE r.organisation_id=v.organisation_id AND r.member_id=v.member_id AND r.event_id=v.event_id
                AND r.session_hash=v.session_hash AND r.state='riding' AND r.expires_at>now() AND p.response='going'))""",
                              (participant, room)).fetchone() is not None

    @app.get('/internal/voice-authorize', status_code=204, include_in_schema=False)
    def authorize_voice(request: Request):
        # Called only by the VM Nginx auth_request subrequest. Port 7880 is
        # loopback-only, so every remote join/reconnect passes this gate.
        if not request.client or request.client.host not in ('127.0.0.1', '::1'):
            raise HTTPException(403, 'Internal request required.')
        key, secret = voice_config()
        try:
            original = request.headers.get('x-original-uri', '')
            if len(original) > 16000:
                raise ValueError('Oversized request')
            values = parse_qs(urlsplit(original).query, max_num_fields=64)
            token = values.get('access_token', [None])[0]
            if not token:
                authorization = request.headers.get('authorization', '')
                token = authorization[7:] if authorization.startswith('Bearer ') else None
            claims = jwt.decode(token, secret, algorithms=['HS256'], issuer=key,
                                options={'require': ['exp', 'sub', 'iss']})
            room = claims['video']['room']
            if claims['video'].get('roomJoin') is not True:
                raise ValueError('Not a participant token')
        except (jwt.PyJWTError, ValueError, TypeError, KeyError):
            raise HTTPException(401, 'Voice sign-in is invalid or expired.')
        if not active_voice_identity(room, claims['sub']):
            raise HTTPException(401, 'Your chapter voice session has ended.')
        return Response(status_code=204)

    @app.post(prefix + '/voice')
    def voice(slug: str, body: VoiceBody, member=Depends(identity)):
        key, secret = voice_config()
        expires = min(datetime.now(timezone.utc) + timedelta(hours=1), member['expires_at'])
        room = 'ws-' + str(member['organisation_id']) + ('-' + body.event_id if body.event_id else '-clubhouse')
        grant = uuid4()
        participant = str(member['id']) + ':' + str(grant)
        with connect() as db:
            lock_identity(db, member)
            recent = db.execute("SELECT count(*) AS n FROM voice_grants WHERE organisation_id=%s AND member_id=%s AND created_at>now()-interval '1 minute'", (member['organisation_id'], member['id'])).fetchone()['n']
            if recent >= 6:
                raise HTTPException(429, 'Wait a minute before joining intercom again.')
            if body.event_id:
                rider = active_rider(db, member, body.event_id)
                expires = min(expires, rider['expires_at'])
            db.execute('UPDATE voice_grants SET revoked_at=now() WHERE organisation_id=%s AND member_id=%s AND revoked_at IS NULL', (member['organisation_id'], member['id']))
            db.execute('INSERT INTO voice_grants(id,organisation_id,member_id,session_hash,room_name,participant_identity,event_id,expires_at) VALUES(%s,%s,%s,%s,%s,%s,%s,%s)', (grant, member['organisation_id'], member['id'], member['token_hash'], room, participant, body.event_id, expires))
        token = livekit.AccessToken(key, secret).with_identity(participant).with_name(member['display_name']).with_ttl(timedelta(seconds=90)).with_grants(livekit.VideoGrants(
            room_join=True, room=room, can_publish=True, can_publish_sources=['microphone'],
            can_subscribe=True, can_publish_data=False, can_update_own_metadata=False)).to_jwt()
        return {'grant_id': str(grant), 'token': token, 'expires_at': expires.isoformat(), 'room_name': room}

    @app.delete(prefix + '/voice/{grant_id}', status_code=204)
    def leave_voice(slug: str, grant_id: UUID, member=Depends(identity)):
        with connect() as db:
            lock_identity(db, member)
            db.execute('UPDATE voice_grants SET revoked_at=now() WHERE id=%s AND organisation_id=%s AND member_id=%s', (grant_id, member['organisation_id'], member['id']))
        return Response(status_code=204)

    def cleanup_rows():
        with connect() as db:
            db.execute("""UPDATE live_riders SET latitude=NULL,longitude=NULL,accuracy=NULL,captured_at=NULL,received_at=NULL
              WHERE (received_at<now()-interval '2 minutes' OR captured_at<now()-interval '2 minutes') AND latitude IS NOT NULL""")
            db.execute("""UPDATE live_riders r SET sharing=false,sharing_id=NULL,latitude=NULL,longitude=NULL,accuracy=NULL,captured_at=NULL,received_at=NULL
              WHERE (r.expires_at<=now() OR r.state<>'riding'
                OR NOT EXISTS(SELECT 1 FROM mobile_sessions s JOIN members m ON m.id=s.member_id AND m.organisation_id=s.organisation_id
                  WHERE s.token_hash=r.session_hash AND s.revoked_at IS NULL AND s.expires_at>now() AND m.status='active'))
              AND (r.sharing OR r.latitude IS NOT NULL)""")
            rows = db.execute("""SELECT v.* FROM voice_grants v WHERE v.removed_at IS NULL AND
              (v.revoked_at IS NOT NULL OR v.expires_at<=now() OR NOT EXISTS(SELECT 1 FROM mobile_sessions s JOIN members m
                ON m.id=s.member_id AND m.organisation_id=s.organisation_id WHERE s.token_hash=v.session_hash
                AND s.revoked_at IS NULL AND s.expires_at>now() AND m.status='active')
                OR (v.event_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM live_riders r WHERE r.organisation_id=v.organisation_id
                  AND r.event_id=v.event_id AND r.member_id=v.member_id AND r.session_hash=v.session_hash
                  AND r.state='riding' AND r.expires_at>now())))""").fetchall()
            db.execute("DELETE FROM live_riders WHERE expires_at<now()-interval '24 hours'")
            db.execute("DELETE FROM voice_grants WHERE removed_at IS NOT NULL AND expires_at<now()-interval '24 hours'")
        return rows

    async def housekeeping():
        while True:
            try:
                rows = await anyio.to_thread.run_sync(cleanup_rows)
                if os.environ.get('WIDOWS_SONS_VOICE_KEY'):
                    key, secret = voice_config()
                    async with livekit.LiveKitAPI(os.environ.get('WIDOWS_SONS_VOICE_INTERNAL', 'http://127.0.0.1:7880'), key, secret) as client:
                        for row in rows:
                            try:
                                await client.room.remove_participant(livekit.RoomParticipantIdentity(room=row['room_name'], identity=row['participant_identity']))
                            except livekit.TwirpError as exc:
                                if exc.code != 'not_found':
                                    continue
                            def mark_removed():
                                with connect() as db:
                                    db.execute('UPDATE voice_grants SET removed_at=now() WHERE id=%s', (row['id'],))
                            await anyio.to_thread.run_sync(mark_removed)
                        # A deleted member/session cascades its grant rows. Scan
                        # real participants as well, so deletion cannot orphan an
                        # already connected audio session. Check each against
                        # current DB state to avoid racing a just-created grant.
                        rooms = await client.room.list_rooms(livekit.ListRoomsRequest())
                        for room in rooms.rooms:
                            if not room.name.startswith('ws-'):
                                continue
                            people = await client.room.list_participants(livekit.ListParticipantsRequest(room=room.name))
                            for person in people.participants:
                                valid = await anyio.to_thread.run_sync(active_voice_identity, room.name, person.identity)
                                if not valid:
                                    with suppress(livekit.TwirpError):
                                        await client.room.remove_participant(livekit.RoomParticipantIdentity(room=room.name, identity=person.identity))
            except asyncio.CancelledError:
                raise
            except Exception:
                # Never log secrets, text or positions; retry the next maintenance tick.
                import logging
                logging.getLogger(__name__).warning('Communications maintenance will retry')
            await asyncio.sleep(15)

    previous_lifespan = app.router.lifespan_context

    @asynccontextmanager
    async def lifespan(application):
        async with previous_lifespan(application):
            task = asyncio.create_task(housekeeping())
            try:
                yield
            finally:
                task.cancel()
                with suppress(asyncio.CancelledError):
                    await task

    app.router.lifespan_context = lifespan
    # Exposed for deterministic expiry/revocation integration checks.
    app.state.community_cleanup = cleanup_rows
    app.state.community_active_voice_identity = active_voice_identity
