-- Apply after schema.sql, as the database owner. No real members are seeded.
BEGIN;
CREATE TABLE IF NOT EXISTS mobile_invites (
 token_hash text PRIMARY KEY,
 organisation_id uuid NOT NULL,
 member_id uuid NOT NULL,
 expires_at timestamptz NOT NULL,
 used_at timestamptz,
 FOREIGN KEY (organisation_id,member_id) REFERENCES members(organisation_id,id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS mobile_sessions (
 token_hash text PRIMARY KEY,
 organisation_id uuid NOT NULL,
 member_id uuid NOT NULL,
 expires_at timestamptz NOT NULL,
 revoked_at timestamptz,
 FOREIGN KEY (organisation_id,member_id) REFERENCES members(organisation_id,id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS mobile_sessions_member ON mobile_sessions(organisation_id,member_id);
CREATE TABLE IF NOT EXISTS mobile_rsvps (
 organisation_id uuid NOT NULL,
 member_id uuid NOT NULL,
 event_id text NOT NULL CHECK(event_id ~ '^cms-[0-9]+$'),
 response text NOT NULL CHECK(response IN ('going','interested','not_going')),
 updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(organisation_id,member_id,event_id),
 FOREIGN KEY (organisation_id,member_id) REFERENCES members(organisation_id,id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS mobile_auth_attempts (
 key text NOT NULL,
 window_start timestamptz NOT NULL,
 attempts integer NOT NULL,
 PRIMARY KEY(key,window_start)
);
COMMIT;
