"""Widows Sons mobile API. Separate process and database role from the public API.

Invitations and sessions are opaque random secrets; only SHA-256 digests are stored.
An invitation is handed to an approved member by a chapter administrator. No email
is sent. Published editorial content comes from this chapter's WordPress instance.
"""
import hashlib
import os
import secrets
from datetime import datetime, timedelta, timezone
from html import unescape
from html.parser import HTMLParser

import httpx
import psycopg
from psycopg.rows import dict_row
from fastapi import Depends, FastAPI, Header, HTTPException, Request, Response
from pydantic import BaseModel, Field

DSN = os.environ.get('WIDOWS_SONS_MOBILE_DSN', 'dbname=widowssons user=widowsapp host=/var/run/postgresql')
CMS_URL = os.environ.get('WIDOWS_SONS_CMS_URL', 'http://127.0.0.1:8080').rstrip('/')
CMS_HOST = os.environ.get('WIDOWS_SONS_CMS_HOST', 'wsmba.the-grange.uk')
CMS_SLUG = os.environ.get('WIDOWS_SONS_CMS_SLUG', 'lr')
app = FastAPI(title='Widows Sons mobile', version='0.6.0')
PREFIX = '/api/v1/mobile'


def connect():
    return psycopg.connect(DSN, row_factory=dict_row)


def digest(token):
    return hashlib.sha256(token.encode()).hexdigest()


class Text(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []
        self.hidden = 0

    def handle_starttag(self, tag, attrs):
        if tag in ('script', 'style'):
            self.hidden += 1
        if tag in ('p', 'br', 'h1', 'h2', 'h3', 'li', 'div'):
            self.parts.append('\n')

    def handle_endtag(self, tag):
        if tag in ('script', 'style'):
            self.hidden = max(0, self.hidden - 1)
        if tag in ('p', 'li', 'h1', 'h2', 'h3', 'div'):
            self.parts.append('\n')

    def handle_data(self, data):
        if not self.hidden:
            self.parts.append(data)


def plain(value):
    parser = Text()
    parser.feed(value or '')
    return '\n\n'.join(line.strip() for line in unescape(''.join(parser.parts)).splitlines() if line.strip())


def chapter(slug):
    with connect() as db:
        row = db.execute('SELECT id,slug,name,display_name,theme FROM organisations WHERE slug=%s', (slug,)).fetchone()
    if not row or slug != CMS_SLUG:
        raise HTTPException(404, 'Chapter not found')
    return row


def cms(path):
    try:
        # Origin is operator configured, never supplied by a member or CMS article.
        result = httpx.get(CMS_URL + path, headers={'Host': CMS_HOST, 'X-Forwarded-Proto': 'https'}, timeout=8, follow_redirects=False)
        result.raise_for_status()
        return result.json()
    except (httpx.HTTPError, ValueError) as exc:
        raise HTTPException(503, 'Chapter updates are temporarily unavailable. Try again shortly.') from exc


def published_events(slug):
    chapter(slug)
    result = cms('/wp-json/widows-sons/v1/events')
    if result.get('organisation') != slug:
        raise HTTPException(503, 'Chapter content could not be verified')
    return result['events']


@app.middleware('http')
async def private_headers(request, call_next):
    response = await call_next(request)
    response.headers['Cache-Control'] = 'no-store'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-Widows-Sons-Environment'] = 'Canada-VM20000'
    return response


@app.get('/health')
def health():
    with connect() as db:
        db.execute('SELECT 1 FROM mobile_sessions LIMIT 1')
    return {'status': 'ok', 'project': 'widows-sons', 'service': 'mobile', 'version': '0.6.0'}


@app.get(PREFIX + '/{slug}/feed')
def feed(slug: str):
    org = chapter(slug)
    posts = cms('/wp-json/wp/v2/posts?per_page=30&status=publish&_fields=id,title,excerpt,content,date_gmt,link')
    pages = cms('/wp-json/wp/v2/pages?slug=about,contact&status=publish&_fields=slug,title,content,link')
    return {
        'chapter': {'slug': org['slug'], 'name': org['name'], 'display_name': org['display_name'], 'theme': org['theme'],
                    'tagline': 'Brotherhood. Bikes. Giving back.', 'website': 'https://' + CMS_HOST,
                    'features': {'news': True, 'events': True, 'membership': True, 'rsvp': True, 'guardian': True,
                                 'intercom': bool(os.environ.get('WIDOWS_SONS_VOICE_KEY')), 'messaging': True, 'tracking': True}},
        'news': [{'id': str(p['id']), 'title': plain(p['title']['rendered']), 'excerpt': plain(p['excerpt']['rendered']),
                  'body': plain(p['content']['rendered']), 'published_at': p['date_gmt'] + 'Z', 'url': p['link']} for p in posts],
        'events': published_events(slug),
        'pages': [{'slug': p['slug'], 'title': plain(p['title']['rendered']), 'body': plain(p['content']['rendered']), 'url': p['link']} for p in pages],
        'updated_at': datetime.now(timezone.utc).isoformat(),
    }


class InviteBody(BaseModel):
    code: str = Field(min_length=40, max_length=150, pattern=r'^[A-Za-z0-9_-]+$')


def throttle(request, slug):
    # Uvicorn trusts forwarding headers only from the loopback Nginx proxy.
    peer = request.client.host if request.client else 'unknown'
    key = digest(slug + ':' + peer)
    with connect() as db:
        db.execute("DELETE FROM mobile_auth_attempts WHERE window_start < now() - interval '1 hour'")
        row = db.execute("""INSERT INTO mobile_auth_attempts(key,window_start,attempts)
            VALUES (%s,date_bin('15 minutes',now(),'2020-01-01'::timestamptz),1)
            ON CONFLICT(key,window_start) DO UPDATE SET attempts=mobile_auth_attempts.attempts+1 RETURNING attempts""", (key,)).fetchone()
    if row['attempts'] > 10:
        raise HTTPException(429, 'Too many attempts. Wait 15 minutes before trying again.', headers={'Retry-After': '900'})


@app.post(PREFIX + '/{slug}/activate')
def activate(slug: str, body: InviteBody, request: Request):
    org = chapter(slug)
    throttle(request, slug)
    token = 'wss_' + secrets.token_urlsafe(32)
    expires = datetime.now(timezone.utc) + timedelta(days=30)
    with connect() as db:
        invite = db.execute("""SELECT i.member_id,m.status FROM mobile_invites i JOIN members m
            ON m.organisation_id=i.organisation_id AND m.id=i.member_id
            WHERE i.token_hash=%s AND i.organisation_id=%s AND i.used_at IS NULL AND i.expires_at>now()
            FOR UPDATE OF i,m""", (digest(body.code), org['id'])).fetchone()
        if not invite or invite['status'] not in ('invited', 'active'):
            raise HTTPException(401, 'This invitation is invalid, expired or already used. Ask the chapter for a new invitation.')
        member = invite['member_id']
        db.execute('UPDATE mobile_invites SET used_at=now() WHERE token_hash=%s', (digest(body.code),))
        db.execute("UPDATE members SET status='active' WHERE organisation_id=%s AND id=%s", (org['id'], member))
        # Reissuing an invitation is also device recovery: old sessions are revoked.
        db.execute('UPDATE mobile_sessions SET revoked_at=now() WHERE organisation_id=%s AND member_id=%s AND revoked_at IS NULL', (org['id'], member))
        db.execute('INSERT INTO mobile_sessions(token_hash,organisation_id,member_id,expires_at) VALUES(%s,%s,%s,%s)', (digest(token), org['id'], member, expires))
        db.execute("INSERT INTO audit_events(organisation_id,actor_id,action,target_id) VALUES(%s,%s,'mobile.activate',%s)", (org['id'], member, member))
    return {'token': token, 'expires_at': expires.isoformat()}


def identity(slug: str, authorization: str | None = Header(default=None)):
    if not authorization or not authorization.startswith('Bearer ') or len(authorization) > 200:
        raise HTTPException(401, 'Please sign in with a chapter invitation.', headers={'WWW-Authenticate': 'Bearer'})
    token = authorization[7:]
    with connect() as db:
        member = db.execute("""SELECT m.id,m.organisation_id,m.display_name,m.membership_type,m.status,o.display_name AS chapter,
            s.expires_at,s.token_hash FROM mobile_sessions s JOIN members m
            ON m.organisation_id=s.organisation_id AND m.id=s.member_id
            JOIN organisations o ON o.id=m.organisation_id
            WHERE s.token_hash=%s AND o.slug=%s AND m.status='active' AND s.revoked_at IS NULL AND s.expires_at>now()""", (digest(token), slug)).fetchone()
    if not member:
        raise HTTPException(401, 'Your sign-in has ended. Ask the chapter for a new invitation.', headers={'WWW-Authenticate': 'Bearer'})
    return member


@app.get(PREFIX + '/{slug}/me')
def me(slug: str, member=Depends(identity)):
    with connect() as db:
        rsvps = db.execute('SELECT event_id,response FROM mobile_rsvps WHERE organisation_id=%s AND member_id=%s', (member['organisation_id'], member['id'])).fetchall()
    return {'id': str(member['id']), 'display_name': member['display_name'], 'membership_type': member['membership_type'],
            'status': member['status'], 'chapter': member['chapter'], 'session_expires_at': member['expires_at'].isoformat(),
            'verified_at': datetime.now(timezone.utc).isoformat(), 'rsvps': {r['event_id']: r['response'] for r in rsvps}}


class RSVPBody(BaseModel):
    response: str = Field(pattern=r'^(going|interested|not_going)$')


@app.put(PREFIX + '/{slug}/events/{event_id}/rsvp')
def rsvp(slug: str, event_id: str, body: RSVPBody, member=Depends(identity)):
    if not any(e['id'] == event_id for e in published_events(slug)):
        raise HTTPException(404, 'This event is no longer available for RSVPs.')
    with connect() as db:
        # Recheck status under a lock, so concurrent suspension cannot accept an RSVP.
        current = db.execute('SELECT status FROM members WHERE organisation_id=%s AND id=%s FOR UPDATE', (member['organisation_id'], member['id'])).fetchone()
        if not current or current['status'] != 'active':
            raise HTTPException(401, 'Your membership is not active.')
        db.execute("""INSERT INTO mobile_rsvps(organisation_id,member_id,event_id,response) VALUES(%s,%s,%s,%s)
            ON CONFLICT(organisation_id,member_id,event_id) DO UPDATE SET response=EXCLUDED.response,updated_at=now()""",
                   (member['organisation_id'], member['id'], event_id, body.response))
        db.execute("INSERT INTO audit_events(organisation_id,actor_id,action,details) VALUES(%s,%s,'mobile.rsvp',jsonb_build_object('event_id',%s::text,'response',%s::text))", (member['organisation_id'], member['id'], event_id, body.response))
        if body.response != 'going':
            from ride_operations import record_end
            record_end(db, member, event_id, 'left')
            db.execute("""UPDATE live_riders SET state='left',sharing=false,sharing_id=NULL,latitude=NULL,longitude=NULL,
              accuracy=NULL,captured_at=NULL,received_at=NULL WHERE organisation_id=%s AND member_id=%s AND event_id=%s""",
                       (member['organisation_id'], member['id'], event_id))
            db.execute('UPDATE voice_grants SET revoked_at=now() WHERE organisation_id=%s AND member_id=%s AND event_id=%s AND revoked_at IS NULL', (member['organisation_id'], member['id'], event_id))
    return {'event_id': event_id, 'response': body.response}


@app.delete(PREFIX + '/{slug}/session', status_code=204)
def sign_out(slug: str, member=Depends(identity)):
    with connect() as db:
        db.execute('UPDATE mobile_sessions SET revoked_at=now() WHERE token_hash=%s', (member['token_hash'],))
    return Response(status_code=204)


from community import install_community
install_community(app, connect, identity, lambda path: cms(path), lambda slug: chapter(slug))
