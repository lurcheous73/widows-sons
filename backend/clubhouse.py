"""Membership-scoped community sections, discussions and informal chapter polls.

No public section directory, welfare data, background notifications or binding
ballots. Ordinary chapter administration never implies private-content access.
"""
from datetime import datetime, timezone, timedelta
from uuid import UUID, uuid4

from fastapi import Depends, HTTPException, Query, Response
from pydantic import BaseModel, Field, field_validator, model_validator
from psycopg.types.json import Jsonb


def clean(value):
    value = value.strip()
    if any(ord(c) < 32 and c not in '\n\t' for c in value) or '\x7f' in value:
        raise ValueError('Remove control characters')
    return value


class SectionBody(BaseModel):
    client_id: UUID = Field(default_factory=uuid4)
    title: str = Field(min_length=1, max_length=100)
    description: str = Field(default='', max_length=2000)
    join_policy: str = Field(pattern=r'^(open|approval|invite)$')
    state: str = Field(default='active', pattern=r'^(active|paused|archived)$')
    revision: int = Field(default=0, ge=0)

    @field_validator('title', 'description')
    @classmethod
    def text(cls, value, info):
        value = clean(value)
        if info.field_name == 'title' and not value:
            raise ValueError('Enter a section name')
        return value


class MembershipAction(BaseModel):
    action: str = Field(pattern=r'^(invite|approve|decline|remove|promote|demote)$')


class PostBody(BaseModel):
    client_id: UUID
    kind: str = Field(pattern=r'^(discussion|announcement|poll)$')
    title: str = Field(min_length=1, max_length=150)
    body: str = Field(default='', max_length=6000)
    options: list[str] = Field(default_factory=list, max_length=8)
    closes_at: datetime | None = None

    @field_validator('title', 'body')
    @classmethod
    def text(cls, value, info):
        value = clean(value)
        if info.field_name == 'title' and not value:
            raise ValueError('Enter a post title')
        return value

    @model_validator(mode='after')
    def poll(self):
        self.options = [clean(v) for v in self.options]
        if self.kind == 'poll':
            if not 2 <= len(self.options) <= 8 or any(not v or len(v) > 150 for v in self.options):
                raise ValueError('Use two to eight options of up to 150 characters')
            if len({v.casefold() for v in self.options}) != len(self.options):
                raise ValueError('Use distinct poll options')
            if self.closes_at is None or self.closes_at.tzinfo is None:
                raise ValueError('Set a poll closing time with a time zone')
        elif self.options or self.closes_at:
            raise ValueError('Only polls have options or closing times')
        return self


class CommentBody(BaseModel):
    client_id: UUID
    body: str = Field(min_length=1, max_length=2000)

    @field_validator('body')
    @classmethod
    def text(cls, value):
        value = clean(value)
        if not value:
            raise ValueError('Enter a comment')
        return value


class VoteBody(BaseModel):
    option_id: UUID


class ContentAction(BaseModel):
    action: str = Field(pattern=r'^(pin|unpin|close|remove)$')
    reason: str = Field(default='', max_length=1000)

    @field_validator('reason')
    @classmethod
    def text(cls, value):
        return clean(value)


class ReportBody(BaseModel):
    reason: str = Field(min_length=5, max_length=500)
    comment_id: int | None = Field(default=None, ge=1)

    @field_validator('reason')
    @classmethod
    def text(cls, value):
        value = clean(value)
        if len(value) < 5:
            raise ValueError('Describe the concern in at least five characters')
        return value


class ResolveBody(BaseModel):
    reason: str = Field(min_length=5, max_length=500)

    @field_validator('reason')
    @classmethod
    def text(cls, value):
        value = clean(value)
        if len(value) < 5:
            raise ValueError('Describe the outcome')
        return value


def log(db, member, section_id, action, target=None, note=''):
    db.execute('INSERT INTO clubhouse_activity(organisation_id,section_id,actor_id,target_id,action,note) VALUES(%s,%s,%s,%s,%s,%s)',
               (member['organisation_id'], section_id, member['id'], target, action, note))


def manager(db, member):
    return bool(db.execute("SELECT 1 FROM role_grants WHERE organisation_id=%s AND member_id=%s AND capability='section.manage' AND scope_type='organisation' AND scope_id IS NULL",
                           (member['organisation_id'], member['id'])).fetchone())


def current(db, member):
    # Recheck under this transaction, including a sign-out between dependency and
    # handler. Share locks prevent concurrent account/session revocation mid-write.
    if not db.execute("""SELECT 1 FROM members m JOIN mobile_sessions s ON s.organisation_id=m.organisation_id AND s.member_id=m.id
        WHERE m.organisation_id=%s AND m.id=%s AND m.status='active' AND s.token_hash=%s
          AND s.revoked_at IS NULL AND s.expires_at>now() FOR SHARE OF m,s""",
                      (member['organisation_id'], member['id'], member['token_hash'])).fetchone():
        raise HTTPException(401, 'Your sign-in has ended. Verify your membership again.')


def section(db, member, section_id, content=False, write=False, moderate=False):
    # All per-section changes share this lock, so removal and content writes cannot
    # race each other. IDs from another tenant never reveal that they exist.
    db.execute('SELECT pg_advisory_xact_lock(hashtextextended(%s,0))', ('clubhouse:' + str(section_id),))
    current(db, member)
    row = db.execute("""SELECT s.*,COALESCE(m.state,'none') AS membership,COALESCE(m.role,'member') AS role
        FROM clubhouse_sections s LEFT JOIN clubhouse_memberships m ON m.organisation_id=s.organisation_id AND m.section_id=s.id AND m.member_id=%s
        WHERE s.organisation_id=%s AND s.id=%s""", (member['id'], member['organisation_id'], section_id)).fetchone()
    if not row:
        raise HTTPException(404, 'Section not found')
    if row['join_policy'] == 'invite' and row['membership'] not in ('active', 'invited', 'requested') and not manager(db, member):
        raise HTTPException(404, 'Section not found')
    if content and (row['membership'] != 'active' or row['state'] == 'paused'):
        raise HTTPException(403, 'Section membership and an available section are required.')
    if write and row['state'] != 'active':
        raise HTTPException(409, 'This section is read-only or paused.')
    if moderate and (row['membership'] != 'active' or row['role'] != 'moderator'):
        raise HTTPException(403, 'This action requires a moderator of this section.')
    return row


def summary(row, can_manage=False):
    active = row['membership'] == 'active'
    return {key: row[key] for key in ('id', 'title', 'description', 'join_policy', 'state', 'revision', 'membership', 'role')} | {
        'can_read': active and row['state'] != 'paused',
        'can_post': active and row['state'] == 'active',
        'can_moderate': active and row['role'] == 'moderator' and row['state'] == 'active',
        'can_configure': can_manage and active and row['role'] == 'moderator'}


def post(db, member, row, post_id):
    result = db.execute('SELECT * FROM clubhouse_posts WHERE organisation_id=%s AND section_id=%s AND id=%s',
                        (member['organisation_id'], row['id'], post_id)).fetchone()
    if not result:
        raise HTTPException(404, 'Post not found')
    return result


def present_post(db, member, row):
    removed = row['removed_at'] is not None
    counts = {str(r['option_id']): r['total'] for r in db.execute('SELECT option_id,count(*) AS total FROM clubhouse_votes WHERE organisation_id=%s AND post_id=%s GROUP BY option_id',
                                                                (member['organisation_id'], row['id'])).fetchall()}
    mine = db.execute('SELECT option_id FROM clubhouse_votes WHERE organisation_id=%s AND post_id=%s AND member_id=%s',
                      (member['organisation_id'], row['id'], member['id'])).fetchone()
    name = db.execute('SELECT display_name FROM members WHERE organisation_id=%s AND id=%s', (member['organisation_id'], row['author_id'])).fetchone()
    replies = db.execute('SELECT count(*) AS total FROM clubhouse_comments WHERE organisation_id=%s AND post_id=%s', (member['organisation_id'], row['id'])).fetchone()['total']
    return {key: row[key] for key in ('id', 'section_id', 'author_id', 'client_id', 'kind', 'created_at', 'closes_at', 'closed_at', 'pinned')} | {
        'author': name['display_name'], 'title': 'Removed post' if removed else row['title'], 'body': '' if removed else row['body'],
        'removed': removed, 'comment_count': replies, 'my_vote': None if removed or not mine else mine['option_id'],
        'options': [] if removed else [o | {'votes': counts.get(o['id'], 0)} for o in row['options']],
        'poll_open': not removed and row['kind'] == 'poll' and row['closed_at'] is None and row['closes_at'] > datetime.now(timezone.utc)}


def last_moderator(db, member, row, target):
    existing = db.execute('SELECT * FROM clubhouse_memberships WHERE organisation_id=%s AND section_id=%s AND member_id=%s',
                          (member['organisation_id'], row['id'], target)).fetchone()
    if existing and existing['state'] == 'active' and existing['role'] == 'moderator':
        others = db.execute("""SELECT count(*) AS total FROM clubhouse_memberships cm JOIN members m ON m.organisation_id=cm.organisation_id AND m.id=cm.member_id
            WHERE cm.organisation_id=%s AND cm.section_id=%s AND cm.state='active' AND cm.role='moderator' AND cm.member_id<>%s AND m.status='active'""",
                            (member['organisation_id'], row['id'], target)).fetchone()['total']
        if not others and row['state'] != 'archived':
            raise HTTPException(409, 'Appoint another active moderator before the last moderator leaves or steps down.')
    return existing


def install_clubhouse(app, connect, identity):
    base = '/api/v1/mobile/{slug}/sections'

    @app.get(base)
    def sections(slug: str, member=Depends(identity)):
        with connect() as db:
            current(db, member)
            can_manage = manager(db, member)
            rows = db.execute("""SELECT s.*,COALESCE(m.state,'none') AS membership,COALESCE(m.role,'member') AS role
                FROM clubhouse_sections s LEFT JOIN clubhouse_memberships m ON m.organisation_id=s.organisation_id AND m.section_id=s.id AND m.member_id=%s
                WHERE s.organisation_id=%s AND (s.join_policy<>'invite' OR m.state IN ('active','invited','requested') OR %s)
                ORDER BY s.created_at,s.id LIMIT 200""", (member['id'], member['organisation_id'], can_manage)).fetchall()
            return {'can_create': can_manage, 'sections': [summary(r, can_manage) for r in rows]}

    @app.post(base)
    def create_section(slug: str, body: SectionBody, member=Depends(identity)):
        with connect() as db:
            current(db, member)
            if not manager(db, member):
                raise HTTPException(403, 'Chapter section.manage permission is required.')
            db.execute('SELECT pg_advisory_xact_lock(hashtextextended(%s,0))', ('club-section:' + str(member['id']) + ':' + str(body.client_id),))
            existing = db.execute('SELECT id FROM clubhouse_sections WHERE organisation_id=%s AND creator_id=%s AND client_id=%s', (member['organisation_id'], member['id'], body.client_id)).fetchone()
            if existing:
                return existing
            # Creating explicitly enrols the creator as moderator; the UI discloses
            # this. No existing private group is opened by this capability.
            row = db.execute('INSERT INTO clubhouse_sections(organisation_id,creator_id,client_id,title,description,join_policy,state) VALUES(%s,%s,%s,%s,%s,%s,%s) RETURNING id',
                             (member['organisation_id'], member['id'], body.client_id, body.title, body.description, body.join_policy, body.state)).fetchone()
            db.execute("INSERT INTO clubhouse_memberships(organisation_id,section_id,member_id,state,role) VALUES(%s,%s,%s,'active','moderator')", (member['organisation_id'], row['id'], member['id']))
            log(db, member, row['id'], 'section.created', note='Creator explicitly joined as moderator; policy=' + body.join_policy)
            return {'id': row['id']}

    @app.get(base + '/{section_id}')
    def section_info(slug: str, section_id: UUID, member=Depends(identity)):
        with connect() as db:
            row = section(db, member, section_id)
            return summary(row, manager(db, member))

    @app.put(base + '/{section_id}', status_code=204)
    def configure_section(slug: str, section_id: UUID, body: SectionBody, member=Depends(identity)):
        with connect() as db:
            row = section(db, member, section_id, moderate=True)
            if not manager(db, member):
                raise HTTPException(403, 'Chapter section.manage permission is required as well as section membership.')
            if body.revision != row['revision']:
                raise HTTPException(409, 'The section has changed. Refresh before saving.')
            db.execute('UPDATE clubhouse_sections SET title=%s,description=%s,join_policy=%s,state=%s,revision=revision+1 WHERE organisation_id=%s AND id=%s',
                       (body.title, body.description, body.join_policy, body.state, member['organisation_id'], section_id))
            log(db, member, section_id, 'section.configured', note=f"policy={row['join_policy']}->{body.join_policy}; state={row['state']}->{body.state}")
        return Response(status_code=204)

    @app.post(base + '/{section_id}/join', status_code=204)
    def join_section(slug: str, section_id: UUID, member=Depends(identity)):
        with connect() as db:
            row = section(db, member, section_id, write=True)
            if row['membership'] == 'active' or (row['membership'] == 'requested' and row['join_policy'] == 'approval'):
                return Response(status_code=204)
            if row['membership'] == 'removed':
                raise HTTPException(403, 'Ask a section moderator for a new invitation.')
            if row['join_policy'] == 'invite' and row['membership'] != 'invited':
                raise HTTPException(403, 'A section invitation is required.')
            state = 'active' if row['join_policy'] == 'open' or row['membership'] == 'invited' else 'requested'
            db.execute("""INSERT INTO clubhouse_memberships(organisation_id,section_id,member_id,state) VALUES(%s,%s,%s,%s)
                ON CONFLICT(organisation_id,section_id,member_id) DO UPDATE SET state=EXCLUDED.state,role='member',updated_at=now()""", (member['organisation_id'], section_id, member['id'], state))
            log(db, member, section_id, 'membership.' + state, target=member['id'])
        return Response(status_code=204)

    @app.delete(base + '/{section_id}/membership', status_code=204)
    def leave_section(slug: str, section_id: UUID, member=Depends(identity)):
        with connect() as db:
            row = section(db, member, section_id)
            if row['membership'] not in ('active', 'invited', 'requested'):
                return Response(status_code=204)
            last_moderator(db, member, row, member['id'])
            db.execute("UPDATE clubhouse_memberships SET state='left',role='member',updated_at=now() WHERE organisation_id=%s AND section_id=%s AND member_id=%s AND state IN ('active','invited','requested')", (member['organisation_id'], section_id, member['id']))
            log(db, member, section_id, 'membership.left', target=member['id'])
        return Response(status_code=204)

    @app.get(base + '/{section_id}/members')
    def members(slug: str, section_id: UUID, member=Depends(identity)):
        with connect() as db:
            section(db, member, section_id, content=True, moderate=True)
            rows = db.execute("""SELECT cm.member_id AS id,m.display_name,cm.state,cm.role FROM clubhouse_memberships cm JOIN members m
                ON m.organisation_id=cm.organisation_id AND m.id=cm.member_id WHERE cm.organisation_id=%s AND cm.section_id=%s AND m.status='active'
                AND cm.state IN ('active','invited','requested') ORDER BY cm.state,m.display_name,cm.member_id LIMIT 500""", (member['organisation_id'], section_id)).fetchall()
            return {'members': rows}

    @app.put(base + '/{section_id}/members/{member_id}', status_code=204)
    def membership_action(slug: str, section_id: UUID, member_id: UUID, body: MembershipAction, member=Depends(identity)):
        with connect() as db:
            row = section(db, member, section_id, content=True, write=True, moderate=True)
            if not db.execute("SELECT 1 FROM members WHERE organisation_id=%s AND id=%s AND status='active'", (member['organisation_id'], member_id)).fetchone():
                raise HTTPException(404, 'Active chapter member not found')
            existing = db.execute('SELECT * FROM clubhouse_memberships WHERE organisation_id=%s AND section_id=%s AND member_id=%s', (member['organisation_id'], section_id, member_id)).fetchone()
            if body.action == 'invite':
                if existing and existing['state'] == 'invited':
                    return Response(status_code=204)
                if existing and existing['state'] in ('active', 'requested'):
                    raise HTTPException(409, 'This member already belongs or has requested access.')
                db.execute("""INSERT INTO clubhouse_memberships(organisation_id,section_id,member_id,state) VALUES(%s,%s,%s,'invited')
                    ON CONFLICT(organisation_id,section_id,member_id) DO UPDATE SET state='invited',role='member',updated_at=now()""", (member['organisation_id'], section_id, member_id))
            else:
                allowed = {'approve': ('requested',), 'decline': ('requested', 'invited'), 'remove': ('active', 'invited', 'requested'), 'promote': ('active',), 'demote': ('active',)}
                if not existing or existing['state'] not in allowed[body.action]:
                    raise HTTPException(409, 'Refresh the section membership before changing it.')
                if body.action in ('remove', 'demote'):
                    last_moderator(db, member, row, member_id)
                state = {'approve': 'active', 'decline': 'declined', 'remove': 'removed'}.get(body.action, existing['state'])
                role = 'moderator' if body.action == 'promote' else 'member' if body.action in ('demote', 'remove', 'decline') else existing['role']
                db.execute('UPDATE clubhouse_memberships SET state=%s,role=%s,updated_at=now() WHERE organisation_id=%s AND section_id=%s AND member_id=%s', (state, role, member['organisation_id'], section_id, member_id))
            log(db, member, section_id, 'membership.' + body.action, target=member_id)
        return Response(status_code=204)

    @app.get(base + '/{section_id}/posts')
    def posts(slug: str, section_id: UUID, before_id: UUID | None = None, member=Depends(identity)):
        with connect() as db:
            row = section(db, member, section_id, content=True)
            cursor = post(db, member, row, before_id)['created_at'] if before_id else None
            rows = db.execute('''SELECT * FROM clubhouse_posts WHERE organisation_id=%s AND section_id=%s
                AND (%s::timestamptz IS NULL OR (created_at,id)<(%s,%s)) ORDER BY created_at DESC,id DESC LIMIT 31''',
                              (member['organisation_id'], section_id, cursor, cursor, before_id)).fetchall()
            return {'posts': [present_post(db, member, r) for r in rows[:30]], 'has_older': len(rows) > 30}

    @app.post(base + '/{section_id}/posts')
    def create_post(slug: str, section_id: UUID, body: PostBody, member=Depends(identity)):
        with connect() as db:
            row = section(db, member, section_id, content=True, write=True)
            if body.kind == 'announcement' and row['role'] != 'moderator':
                raise HTTPException(403, 'Only section moderators can publish announcements.')
            db.execute('SELECT pg_advisory_xact_lock(hashtextextended(%s,0))', ('club-post:' + str(member['id']) + ':' + str(body.client_id),))
            existing = db.execute('SELECT * FROM clubhouse_posts WHERE organisation_id=%s AND author_id=%s AND client_id=%s', (member['organisation_id'], member['id'], body.client_id)).fetchone()
            if existing:
                if existing['section_id'] != section_id:
                    raise HTTPException(409, 'This send identifier was already used in another section.')
                return present_post(db, member, existing)
            if body.kind == 'poll' and not datetime.now(timezone.utc) < body.closes_at <= datetime.now(timezone.utc) + timedelta(days=90):
                raise HTTPException(422, 'Close the poll within the next 90 days.')
            recent = db.execute("SELECT count(*) AS total FROM clubhouse_posts WHERE organisation_id=%s AND author_id=%s AND created_at>now()-interval '1 minute'", (member['organisation_id'], member['id'])).fetchone()['total']
            if recent >= 10:
                raise HTTPException(429, 'Wait a minute before posting again.')
            options = [{'id': str(uuid4()), 'title': v} for v in body.options]
            created = db.execute('''INSERT INTO clubhouse_posts(organisation_id,section_id,author_id,client_id,kind,title,body,options,closes_at)
                VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING *''', (member['organisation_id'], section_id, member['id'], body.client_id, body.kind, body.title, body.body, Jsonb(options), body.closes_at)).fetchone()
            return present_post(db, member, created)

    @app.get(base + '/{section_id}/posts/{post_id}')
    def post_detail(slug: str, section_id: UUID, post_id: UUID, member=Depends(identity)):
        with connect() as db:
            row = section(db, member, section_id, content=True)
            return present_post(db, member, post(db, member, row, post_id))

    @app.post(base + '/{section_id}/posts/{post_id}/actions', status_code=204)
    def post_action(slug: str, section_id: UUID, post_id: UUID, body: ContentAction, member=Depends(identity)):
        with connect() as db:
            row = section(db, member, section_id, content=True, write=True)
            item = post(db, member, row, post_id)
            if body.action != 'remove' or item['author_id'] != member['id']:
                if row['role'] != 'moderator':
                    raise HTTPException(403, 'A section moderator is required.')
            if body.action == 'remove':
                if len(body.reason) < 5:
                    raise HTTPException(422, 'Record a removal reason of at least five characters.')
                db.execute("UPDATE clubhouse_posts SET removed_at=COALESCE(removed_at,now()),title='Removed post',body='',options='[]',pinned=false WHERE organisation_id=%s AND id=%s", (member['organisation_id'], post_id))
                db.execute('DELETE FROM clubhouse_votes WHERE organisation_id=%s AND post_id=%s', (member['organisation_id'], post_id))
            elif item['removed_at']:
                raise HTTPException(409, 'This post was removed.')
            elif body.action == 'close':
                if item['kind'] != 'poll':
                    raise HTTPException(422, 'Only polls can be closed.')
                db.execute('UPDATE clubhouse_posts SET closed_at=COALESCE(closed_at,now()) WHERE organisation_id=%s AND id=%s', (member['organisation_id'], post_id))
            else:
                db.execute('UPDATE clubhouse_posts SET pinned=%s WHERE organisation_id=%s AND id=%s', (body.action == 'pin', member['organisation_id'], post_id))
            log(db, member, section_id, 'post.' + body.action, target=post_id, note=body.reason)
        return Response(status_code=204)

    def vote_change(db, member, section_id, post_id, option=None):
        row = section(db, member, section_id, content=True, write=True)
        item = post(db, member, row, post_id)
        if item['kind'] != 'poll' or item['removed_at'] or item['closed_at'] or item['closes_at'] <= datetime.now(timezone.utc):
            raise HTTPException(409, 'This poll is closed or unavailable.')
        if option is None:
            db.execute('DELETE FROM clubhouse_votes WHERE organisation_id=%s AND post_id=%s AND member_id=%s', (member['organisation_id'], post_id, member['id']))
        else:
            if str(option) not in [v['id'] for v in item['options']]:
                raise HTTPException(422, 'Choose an option belonging to this poll.')
            db.execute('''INSERT INTO clubhouse_votes(organisation_id,post_id,member_id,option_id) VALUES(%s,%s,%s,%s)
                ON CONFLICT(organisation_id,post_id,member_id) DO UPDATE SET option_id=EXCLUDED.option_id,updated_at=now()''', (member['organisation_id'], post_id, member['id'], option))

    @app.put(base + '/{section_id}/posts/{post_id}/vote', status_code=204)
    def vote(slug: str, section_id: UUID, post_id: UUID, body: VoteBody, member=Depends(identity)):
        with connect() as db:
            vote_change(db, member, section_id, post_id, body.option_id)
        return Response(status_code=204)

    @app.delete(base + '/{section_id}/posts/{post_id}/vote', status_code=204)
    def unvote(slug: str, section_id: UUID, post_id: UUID, member=Depends(identity)):
        with connect() as db:
            vote_change(db, member, section_id, post_id)
        return Response(status_code=204)

    @app.get(base + '/{section_id}/posts/{post_id}/comments')
    def comments(slug: str, section_id: UUID, post_id: UUID, before: int | None = Query(default=None, ge=1), member=Depends(identity)):
        with connect() as db:
            row = section(db, member, section_id, content=True)
            item = post(db, member, row, post_id)
            if item['removed_at']:
                return {'comments': [], 'has_older': False}
            rows = db.execute('''SELECT c.id,c.author_id,m.display_name AS author,c.client_id,c.body,c.created_at,c.removed_at IS NOT NULL AS removed
                FROM clubhouse_comments c JOIN members m ON m.organisation_id=c.organisation_id AND m.id=c.author_id
                WHERE c.organisation_id=%s AND c.post_id=%s AND (%s::bigint IS NULL OR c.id<%s) ORDER BY c.id DESC LIMIT 51''', (member['organisation_id'], post_id, before, before)).fetchall()
            return {'comments': list(reversed(rows[:50])), 'has_older': len(rows) > 50}

    @app.post(base + '/{section_id}/posts/{post_id}/comments')
    def create_comment(slug: str, section_id: UUID, post_id: UUID, body: CommentBody, member=Depends(identity)):
        with connect() as db:
            row = section(db, member, section_id, content=True, write=True)
            item = post(db, member, row, post_id)
            if item['removed_at']:
                raise HTTPException(409, 'This post was removed.')
            db.execute('SELECT pg_advisory_xact_lock(hashtextextended(%s,0))', ('club-comment:' + str(member['id']) + ':' + str(body.client_id),))
            existing = db.execute('SELECT id,post_id,author_id,client_id FROM clubhouse_comments WHERE organisation_id=%s AND author_id=%s AND client_id=%s', (member['organisation_id'], member['id'], body.client_id)).fetchone()
            if existing:
                if existing['post_id'] != post_id:
                    raise HTTPException(409, 'This send identifier was already used on another post.')
                return existing
            recent = db.execute("SELECT count(*) AS total FROM clubhouse_comments WHERE organisation_id=%s AND author_id=%s AND created_at>now()-interval '1 minute'", (member['organisation_id'], member['id'])).fetchone()['total']
            if recent >= 30:
                raise HTTPException(429, 'Wait a minute before commenting again.')
            return db.execute('INSERT INTO clubhouse_comments(organisation_id,post_id,author_id,client_id,body) VALUES(%s,%s,%s,%s,%s) RETURNING id,post_id,author_id,client_id', (member['organisation_id'], post_id, member['id'], body.client_id, body.body)).fetchone()

    @app.post(base + '/{section_id}/posts/{post_id}/comments/{comment_id}/remove', status_code=204)
    def remove_comment(slug: str, section_id: UUID, post_id: UUID, comment_id: int, body: ResolveBody, member=Depends(identity)):
        with connect() as db:
            row = section(db, member, section_id, content=True, write=True)
            post(db, member, row, post_id)
            item = db.execute('SELECT author_id FROM clubhouse_comments WHERE organisation_id=%s AND post_id=%s AND id=%s', (member['organisation_id'], post_id, comment_id)).fetchone()
            if not item:
                raise HTTPException(404, 'Comment not found')
            if item['author_id'] != member['id'] and row['role'] != 'moderator':
                raise HTTPException(403, 'Only the author or a section moderator can remove this comment.')
            db.execute("UPDATE clubhouse_comments SET removed_at=COALESCE(removed_at,now()),body='' WHERE organisation_id=%s AND post_id=%s AND id=%s", (member['organisation_id'], post_id, comment_id))
            log(db, member, section_id, 'comment.removed', target=post_id, note=f'comment={comment_id}; ' + body.reason)
        return Response(status_code=204)

    @app.post(base + '/{section_id}/posts/{post_id}/reports', status_code=204)
    def report(slug: str, section_id: UUID, post_id: UUID, body: ReportBody, member=Depends(identity)):
        with connect() as db:
            row = section(db, member, section_id, content=True, write=True)
            post(db, member, row, post_id)
            if body.comment_id and not db.execute('SELECT 1 FROM clubhouse_comments WHERE organisation_id=%s AND post_id=%s AND id=%s', (member['organisation_id'], post_id, body.comment_id)).fetchone():
                raise HTTPException(404, 'Comment not found in this post')
            count = db.execute("SELECT count(*) AS total FROM clubhouse_reports WHERE organisation_id=%s AND member_id=%s AND created_at>now()-interval '1 hour'", (member['organisation_id'], member['id'])).fetchone()['total']
            if count >= 20:
                raise HTTPException(429, 'Your reports have been saved. Try again later.')
            db.execute('INSERT INTO clubhouse_reports(organisation_id,post_id,comment_id,member_id,reason) VALUES(%s,%s,%s,%s,%s)', (member['organisation_id'], post_id, body.comment_id, member['id'], body.reason))
        return Response(status_code=204)

    @app.get(base + '/{section_id}/moderation')
    def moderation(slug: str, section_id: UUID, member=Depends(identity)):
        with connect() as db:
            section(db, member, section_id, content=True, moderate=True)
            reports = db.execute('''SELECT r.id,r.post_id,r.comment_id,r.reason,r.created_at FROM clubhouse_reports r JOIN clubhouse_posts p ON p.organisation_id=r.organisation_id AND p.id=r.post_id
                WHERE p.organisation_id=%s AND p.section_id=%s AND r.resolved_at IS NULL ORDER BY r.created_at LIMIT 100''', (member['organisation_id'], section_id)).fetchall()
            activity = db.execute('SELECT id,actor_id,target_id,action,note,created_at FROM clubhouse_activity WHERE organisation_id=%s AND section_id=%s ORDER BY id DESC LIMIT 100', (member['organisation_id'], section_id)).fetchall()
            return {'reports': reports, 'activity': activity}

    @app.post(base + '/{section_id}/reports/{report_id}/resolve', status_code=204)
    def resolve_report(slug: str, section_id: UUID, report_id: UUID, body: ResolveBody, member=Depends(identity)):
        with connect() as db:
            section(db, member, section_id, content=True, write=True, moderate=True)
            result = db.execute('''UPDATE clubhouse_reports r SET resolved_at=COALESCE(resolved_at,now()),resolution=%s FROM clubhouse_posts p
                WHERE r.organisation_id=%s AND r.id=%s AND p.organisation_id=r.organisation_id AND p.id=r.post_id AND p.section_id=%s RETURNING r.id''', (body.reason, member['organisation_id'], report_id, section_id)).fetchone()
            if not result:
                raise HTTPException(404, 'Report not found')
            log(db, member, section_id, 'report.resolved', target=report_id, note=body.reason)
        return Response(status_code=204)
