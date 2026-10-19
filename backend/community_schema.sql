-- Additive communications schema. Apply as database owner after mobile_schema.sql.
BEGIN;
CREATE TABLE IF NOT EXISTS conversations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organisation_id uuid NOT NULL REFERENCES organisations(id) ON DELETE CASCADE,
 kind text NOT NULL CHECK(kind IN ('chapter','direct','ride')),
 scope_key text NOT NULL,
 title text NOT NULL,
 event_id text,
 first_member uuid,
 second_member uuid,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(organisation_id,id), UNIQUE(organisation_id,scope_key),
 FOREIGN KEY(organisation_id,first_member) REFERENCES members(organisation_id,id) ON DELETE CASCADE,
 FOREIGN KEY(organisation_id,second_member) REFERENCES members(organisation_id,id) ON DELETE CASCADE,
 CHECK((kind='direct' AND first_member IS NOT NULL AND second_member IS NOT NULL AND first_member<>second_member)
   OR (kind<>'direct' AND first_member IS NULL AND second_member IS NULL)),
 CHECK((kind='ride' AND event_id ~ '^cms-[0-9]+$') OR (kind<>'ride' AND event_id IS NULL))
);
CREATE TABLE IF NOT EXISTS conversation_messages (
 id bigserial PRIMARY KEY,
 organisation_id uuid NOT NULL,
 conversation_id uuid NOT NULL,
 sender_id uuid NOT NULL,
 client_id uuid NOT NULL,
 body text NOT NULL CHECK(char_length(body)<=2000),
 sent_at timestamptz NOT NULL DEFAULT now(),
 deleted_at timestamptz,
 FOREIGN KEY(organisation_id,conversation_id) REFERENCES conversations(organisation_id,id) ON DELETE CASCADE,
 FOREIGN KEY(organisation_id,sender_id) REFERENCES members(organisation_id,id) ON DELETE CASCADE,
 UNIQUE(organisation_id,sender_id,client_id)
);
CREATE INDEX IF NOT EXISTS conversation_history ON conversation_messages(organisation_id,conversation_id,id DESC);
CREATE TABLE IF NOT EXISTS conversation_reads (
 organisation_id uuid NOT NULL,
 conversation_id uuid NOT NULL,
 member_id uuid NOT NULL,
 last_read_id bigint NOT NULL DEFAULT 0,
 PRIMARY KEY(organisation_id,conversation_id,member_id),
 FOREIGN KEY(organisation_id,conversation_id) REFERENCES conversations(organisation_id,id) ON DELETE CASCADE,
 FOREIGN KEY(organisation_id,member_id) REFERENCES members(organisation_id,id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS member_blocks (
 organisation_id uuid NOT NULL,
 member_id uuid NOT NULL,
 blocked_id uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(organisation_id,member_id,blocked_id),
 FOREIGN KEY(organisation_id,member_id) REFERENCES members(organisation_id,id) ON DELETE CASCADE,
 FOREIGN KEY(organisation_id,blocked_id) REFERENCES members(organisation_id,id) ON DELETE CASCADE,
 CHECK(member_id<>blocked_id)
);
CREATE TABLE IF NOT EXISTS message_reports (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organisation_id uuid NOT NULL,
 message_id bigint NOT NULL REFERENCES conversation_messages(id) ON DELETE CASCADE,
 member_id uuid NOT NULL,
 reason text NOT NULL CHECK(char_length(reason) BETWEEN 1 AND 500),
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(organisation_id,member_id) REFERENCES members(organisation_id,id) ON DELETE CASCADE,
 UNIQUE(organisation_id,message_id,member_id)
);
CREATE TABLE IF NOT EXISTS live_riders (
 organisation_id uuid NOT NULL,
 event_id text NOT NULL CHECK(event_id ~ '^cms-[0-9]+$'),
 member_id uuid NOT NULL,
 session_hash text NOT NULL REFERENCES mobile_sessions(token_hash) ON DELETE CASCADE,
 joined_at timestamptz NOT NULL DEFAULT now(),
 expires_at timestamptz NOT NULL,
 state text NOT NULL DEFAULT 'riding' CHECK(state IN ('riding','home','left')),
 sharing boolean NOT NULL DEFAULT false,
 sharing_id uuid,
 latitude double precision CHECK(latitude BETWEEN -90 AND 90),
 longitude double precision CHECK(longitude BETWEEN -180 AND 180),
 accuracy double precision CHECK(accuracy BETWEEN 0 AND 1000),
 captured_at timestamptz,
 received_at timestamptz,
 checked_in_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(organisation_id,event_id,member_id),
 FOREIGN KEY(organisation_id,member_id) REFERENCES members(organisation_id,id) ON DELETE CASCADE
);
ALTER TABLE live_riders ADD COLUMN IF NOT EXISTS sharing_id uuid;
CREATE TABLE IF NOT EXISTS voice_grants (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organisation_id uuid NOT NULL,
 member_id uuid NOT NULL,
 session_hash text NOT NULL REFERENCES mobile_sessions(token_hash) ON DELETE CASCADE,
 room_name text NOT NULL,
 participant_identity text NOT NULL UNIQUE,
 event_id text,
 created_at timestamptz NOT NULL DEFAULT now(),
 expires_at timestamptz NOT NULL,
 revoked_at timestamptz,
 removed_at timestamptz,
 FOREIGN KEY(organisation_id,member_id) REFERENCES members(organisation_id,id) ON DELETE CASCADE
);
ALTER TABLE voice_grants ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
COMMIT;
