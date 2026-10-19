-- Ordinary community groups only. Legacy community_sections/section_members and
-- confidential welfare are deliberately not migrated or granted to this service.
BEGIN;
CREATE TABLE IF NOT EXISTS clubhouse_sections (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organisation_id uuid NOT NULL REFERENCES organisations(id) ON DELETE CASCADE,
 creator_id uuid NOT NULL,
 client_id uuid NOT NULL,
 title text NOT NULL CHECK(char_length(title) BETWEEN 1 AND 100),
 description text NOT NULL DEFAULT '' CHECK(char_length(description)<=2000),
 join_policy text NOT NULL CHECK(join_policy IN ('open','approval','invite')),
 state text NOT NULL DEFAULT 'active' CHECK(state IN ('active','paused','archived')),
 revision integer NOT NULL DEFAULT 0,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(organisation_id,id), UNIQUE(organisation_id,creator_id,client_id)
);
CREATE TABLE IF NOT EXISTS clubhouse_memberships (
 organisation_id uuid NOT NULL,
 section_id uuid NOT NULL,
 member_id uuid NOT NULL,
 state text NOT NULL CHECK(state IN ('active','invited','requested','declined','removed','left')),
 role text NOT NULL DEFAULT 'member' CHECK(role IN ('member','moderator')),
 updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(organisation_id,section_id,member_id),
 FOREIGN KEY(organisation_id,section_id) REFERENCES clubhouse_sections(organisation_id,id) ON DELETE CASCADE,
 FOREIGN KEY(organisation_id,member_id) REFERENCES members(organisation_id,id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS clubhouse_posts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organisation_id uuid NOT NULL,
 section_id uuid NOT NULL,
 author_id uuid NOT NULL,
 client_id uuid NOT NULL,
 kind text NOT NULL CHECK(kind IN ('discussion','announcement','poll')),
 title text NOT NULL CHECK(char_length(title) BETWEEN 1 AND 150),
 body text NOT NULL CHECK(char_length(body)<=6000),
 options jsonb NOT NULL DEFAULT '[]'::jsonb,
 closes_at timestamptz,
 closed_at timestamptz,
 pinned boolean NOT NULL DEFAULT false,
 removed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(organisation_id,id), UNIQUE(organisation_id,author_id,client_id),
 FOREIGN KEY(organisation_id,section_id) REFERENCES clubhouse_sections(organisation_id,id) ON DELETE CASCADE,
 FOREIGN KEY(organisation_id,author_id) REFERENCES members(organisation_id,id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS clubhouse_posts_recent ON clubhouse_posts(organisation_id,section_id,created_at DESC,id DESC);
CREATE TABLE IF NOT EXISTS clubhouse_comments (
 id bigserial PRIMARY KEY,
 organisation_id uuid NOT NULL,
 post_id uuid NOT NULL,
 author_id uuid NOT NULL,
 client_id uuid NOT NULL,
 body text NOT NULL CHECK(char_length(body)<=2000),
 removed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(organisation_id,author_id,client_id), UNIQUE(organisation_id,post_id,id),
 CHECK((removed_at IS NOT NULL AND body='') OR (removed_at IS NULL AND char_length(body) BETWEEN 1 AND 2000)),
 FOREIGN KEY(organisation_id,post_id) REFERENCES clubhouse_posts(organisation_id,id) ON DELETE CASCADE,
 FOREIGN KEY(organisation_id,author_id) REFERENCES members(organisation_id,id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS clubhouse_votes (
 organisation_id uuid NOT NULL,
 post_id uuid NOT NULL,
 member_id uuid NOT NULL,
 option_id uuid NOT NULL,
 updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(organisation_id,post_id,member_id),
 FOREIGN KEY(organisation_id,post_id) REFERENCES clubhouse_posts(organisation_id,id) ON DELETE CASCADE,
 FOREIGN KEY(organisation_id,member_id) REFERENCES members(organisation_id,id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS clubhouse_reports (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organisation_id uuid NOT NULL,
 post_id uuid NOT NULL,
 comment_id bigint,
 member_id uuid NOT NULL,
 reason text NOT NULL CHECK(char_length(reason) BETWEEN 5 AND 500),
 resolved_at timestamptz,
 resolution text,
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(organisation_id,post_id) REFERENCES clubhouse_posts(organisation_id,id) ON DELETE CASCADE,
 FOREIGN KEY(organisation_id,member_id) REFERENCES members(organisation_id,id) ON DELETE CASCADE,
 FOREIGN KEY(organisation_id,post_id,comment_id) REFERENCES clubhouse_comments(organisation_id,post_id,id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS clubhouse_reports_pending ON clubhouse_reports(organisation_id,post_id) WHERE resolved_at IS NULL;
CREATE TABLE IF NOT EXISTS clubhouse_activity (
 id bigserial PRIMARY KEY,
 organisation_id uuid NOT NULL,
 section_id uuid NOT NULL,
 actor_id uuid,
 target_id uuid,
 action text NOT NULL,
 note text NOT NULL DEFAULT '' CHECK(char_length(note)<=1000),
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(organisation_id,section_id) REFERENCES clubhouse_sections(organisation_id,id) ON DELETE CASCADE
);
COMMIT;
