-- Widows Sons shared PostgreSQL foundation. No real personal data is seeded.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE TABLE IF NOT EXISTS organisations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 slug text NOT NULL UNIQUE CHECK(slug ~ '^[a-z0-9-]{2,50}$'),
 name text NOT NULL,
 display_name text NOT NULL,
 theme jsonb NOT NULL DEFAULT '{}'::jsonb,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS members (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organisation_id uuid NOT NULL REFERENCES organisations(id) ON DELETE CASCADE,
 email text NOT NULL,
 display_name text NOT NULL,
 status text NOT NULL DEFAULT 'invited' CHECK(status IN ('invited','active','suspended','left')),
 membership_type text NOT NULL DEFAULT 'member' CHECK(membership_type IN ('member','associate','guest')),
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(organisation_id,email),
 UNIQUE(organisation_id,id)
);
CREATE TABLE IF NOT EXISTS role_grants (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organisation_id uuid NOT NULL REFERENCES organisations(id) ON DELETE CASCADE,
 member_id uuid NOT NULL,
 capability text NOT NULL,
 scope_type text NOT NULL DEFAULT 'organisation',
 scope_id uuid,
 granted_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY (organisation_id, member_id) REFERENCES members(organisation_id,id) ON DELETE CASCADE,
 UNIQUE(organisation_id,member_id,capability,scope_type,scope_id)
);
CREATE TABLE IF NOT EXISTS community_sections (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organisation_id uuid NOT NULL REFERENCES organisations(id) ON DELETE CASCADE,
 title text NOT NULL,
 visibility text NOT NULL CHECK(visibility IN ('members','approved','public')),
 enabled boolean NOT NULL DEFAULT true,
 UNIQUE(organisation_id,id)
);
CREATE TABLE IF NOT EXISTS section_members (
 organisation_id uuid NOT NULL,
 section_id uuid NOT NULL,
 member_id uuid NOT NULL,
 PRIMARY KEY(section_id,member_id),
 FOREIGN KEY (organisation_id,section_id) REFERENCES community_sections(organisation_id,id) ON DELETE CASCADE,
 FOREIGN KEY (organisation_id,member_id) REFERENCES members(organisation_id,id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS chapter_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organisation_id uuid NOT NULL REFERENCES organisations(id) ON DELETE CASCADE,
 title text NOT NULL,
 description text NOT NULL DEFAULT '',
 begins_at timestamptz NOT NULL,
 status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','published','cancelled')),
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(organisation_id,id)
);
CREATE INDEX IF NOT EXISTS idx_chapter_events_public ON chapter_events (organisation_id,begins_at) WHERE status='published';
CREATE TABLE IF NOT EXISTS audit_events (
 id bigserial PRIMARY KEY,
 organisation_id uuid NOT NULL REFERENCES organisations(id),
 actor_id uuid,
 action text NOT NULL,
 target_id uuid,
 timestamp timestamptz NOT NULL DEFAULT now(),
 details jsonb NOT NULL DEFAULT '{}'::jsonb
);
INSERT INTO organisations (slug,name,display_name,theme)
VALUES ('lr','Leicestershire & Rutland Widows Sons','Widows Sons L&R','{"primary":"#20252e","accent":"#c5a365","background":"#10141b"}')
ON CONFLICT (slug) DO NOTHING;
COMMIT;
