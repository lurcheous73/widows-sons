-- Additive ride operations. Road assignments never grant chapter administration.
BEGIN;
CREATE TABLE IF NOT EXISTS ride_managers (
 organisation_id uuid NOT NULL,
 event_id text NOT NULL CHECK(event_id ~ '^cms-[0-9]+$'),
 member_id uuid NOT NULL,
 granted_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(organisation_id,event_id,member_id),
 FOREIGN KEY(organisation_id,member_id) REFERENCES members(organisation_id,id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS ride_plans (
 organisation_id uuid NOT NULL REFERENCES organisations(id) ON DELETE CASCADE,
 event_id text NOT NULL CHECK(event_id ~ '^cms-[0-9]+$'),
 revision integer NOT NULL DEFAULT 0,
 briefing text NOT NULL DEFAULT '' CHECK(char_length(briefing)<=6000),
 meeting_point text NOT NULL DEFAULT '' CHECK(char_length(meeting_point)<=250),
 check_in_minutes integer NOT NULL DEFAULT 15 CHECK(check_in_minutes BETWEEN 5 AND 120),
 stops jsonb NOT NULL DEFAULT '[]'::jsonb,
 route jsonb NOT NULL DEFAULT '[]'::jsonb,
 route_name text NOT NULL DEFAULT '',
 closed_at timestamptz,
 updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(organisation_id,event_id)
);
CREATE TABLE IF NOT EXISTS ride_assignments (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organisation_id uuid NOT NULL,
 event_id text NOT NULL CHECK(event_id ~ '^cms-[0-9]+$'),
 slot text NOT NULL CHECK(slot IN ('lead','sweep','deputy','responder')),
 member_id uuid NOT NULL,
 nominated_by uuid NOT NULL,
 state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','accepted','declined','replaced','withdrawn')),
 nominated_at timestamptz NOT NULL DEFAULT now(),
 accepted_at timestamptz,
 FOREIGN KEY(organisation_id,member_id) REFERENCES members(organisation_id,id) ON DELETE CASCADE,
 FOREIGN KEY(organisation_id,nominated_by) REFERENCES members(organisation_id,id) ON DELETE CASCADE,
 UNIQUE(organisation_id,id)
);
CREATE UNIQUE INDEX IF NOT EXISTS ride_accepted_slot ON ride_assignments(organisation_id,event_id,slot) WHERE state='accepted';
CREATE UNIQUE INDEX IF NOT EXISTS ride_pending_slot ON ride_assignments(organisation_id,event_id,slot) WHERE state='pending';
CREATE UNIQUE INDEX IF NOT EXISTS ride_accepted_member ON ride_assignments(organisation_id,event_id,member_id) WHERE state='accepted';
CREATE TABLE IF NOT EXISTS ride_participation (
 organisation_id uuid NOT NULL,
 event_id text NOT NULL CHECK(event_id ~ '^cms-[0-9]+$'),
 member_id uuid NOT NULL,
 joined_at timestamptz NOT NULL DEFAULT now(),
 expires_at timestamptz NOT NULL,
 state text NOT NULL DEFAULT 'riding' CHECK(state IN ('riding','home','left','assisted')),
 checked_in_at timestamptz NOT NULL DEFAULT now(),
 completed_at timestamptz,
 PRIMARY KEY(organisation_id,event_id,member_id),
 FOREIGN KEY(organisation_id,member_id) REFERENCES members(organisation_id,id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS ride_incidents (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organisation_id uuid NOT NULL,
 event_id text NOT NULL CHECK(event_id ~ '^cms-[0-9]+$'),
 reporter_id uuid NOT NULL,
 subject_id uuid NOT NULL,
 client_id uuid NOT NULL,
 kind text NOT NULL CHECK(kind IN ('help','sos','check_in')),
 note text NOT NULL CHECK(char_length(note)<=1000),
 reported_at timestamptz NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 resolved_at timestamptz,
 resolution text,
 FOREIGN KEY(organisation_id,reporter_id) REFERENCES members(organisation_id,id) ON DELETE CASCADE,
 FOREIGN KEY(organisation_id,subject_id) REFERENCES members(organisation_id,id) ON DELETE CASCADE,
 UNIQUE(organisation_id,id), UNIQUE(organisation_id,reporter_id,client_id)
);
CREATE TABLE IF NOT EXISTS ride_incident_receipts (
 organisation_id uuid NOT NULL,
 incident_id uuid NOT NULL,
 member_id uuid NOT NULL,
 state text NOT NULL CHECK(state IN ('acknowledged','responding')),
 updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(organisation_id,incident_id,member_id),
 FOREIGN KEY(organisation_id,incident_id) REFERENCES ride_incidents(organisation_id,id) ON DELETE CASCADE,
 FOREIGN KEY(organisation_id,member_id) REFERENCES members(organisation_id,id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS ride_activity (
 id bigserial PRIMARY KEY,
 organisation_id uuid NOT NULL REFERENCES organisations(id) ON DELETE CASCADE,
 event_id text NOT NULL CHECK(event_id ~ '^cms-[0-9]+$'),
 actor_id uuid,
 incident_id uuid,
 action text NOT NULL,
 note text NOT NULL DEFAULT '' CHECK(char_length(note)<=1000),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ride_incidents_recent ON ride_incidents(organisation_id,event_id,created_at DESC);
CREATE INDEX IF NOT EXISTS ride_activity_recent ON ride_activity(organisation_id,event_id,id DESC);
COMMIT;
