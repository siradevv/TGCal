-- ============================================================================
-- Migration 003: Community Features
-- Adds crew chat, layover guide, commute tracker, shared roster, crew pairing
-- ============================================================================

-- ============================================================================
-- 1. Crew Chat Channels
-- ============================================================================

CREATE TABLE IF NOT EXISTS crew_channels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    channel_type TEXT NOT NULL DEFAULT 'general'
        CHECK (channel_type IN ('general', 'base', 'fleet', 'rank')),
    description TEXT,
    created_by UUID REFERENCES profiles(id),
    member_count INT NOT NULL DEFAULT 0,
    last_message_text TEXT,
    last_message_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_crew_channels_type ON crew_channels(channel_type);
CREATE INDEX idx_crew_channels_last_msg ON crew_channels(last_message_at DESC NULLS LAST);

-- Channel membership
CREATE TABLE IF NOT EXISTS crew_channel_members (
    channel_id UUID NOT NULL REFERENCES crew_channels(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (channel_id, user_id)
);

-- Channel messages
CREATE TABLE IF NOT EXISTS crew_channel_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    channel_id UUID NOT NULL REFERENCES crew_channels(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES profiles(id),
    sender_name TEXT NOT NULL,
    sender_rank TEXT,
    text TEXT NOT NULL,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_crew_messages_channel ON crew_channel_messages(channel_id, sent_at);

-- Update member count on join/leave
CREATE OR REPLACE FUNCTION update_channel_member_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE crew_channels SET member_count = member_count + 1 WHERE id = NEW.channel_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE crew_channels SET member_count = member_count - 1 WHERE id = OLD.channel_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_channel_member_count
    AFTER INSERT OR DELETE ON crew_channel_members
    FOR EACH ROW EXECUTE FUNCTION update_channel_member_count();

-- RLS for crew channels
ALTER TABLE crew_channels ENABLE ROW LEVEL SECURITY;
ALTER TABLE crew_channel_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE crew_channel_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "channels_read" ON crew_channels FOR SELECT USING (true);
CREATE POLICY "channel_members_read" ON crew_channel_members FOR SELECT USING (true);
CREATE POLICY "channel_members_insert" ON crew_channel_members FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "channel_members_delete" ON crew_channel_members FOR DELETE USING (auth.uid() = user_id);
CREATE POLICY "channel_messages_read" ON crew_channel_messages FOR SELECT USING (true);
CREATE POLICY "channel_messages_insert" ON crew_channel_messages FOR INSERT WITH CHECK (auth.uid() = sender_id);

-- Seed default channels
INSERT INTO crew_channels (name, channel_type, description) VALUES
    ('General', 'general', 'Open discussion for all TG crew'),
    ('BKK Base', 'base', 'Bangkok Suvarnabhumi crew'),
    ('Widebody Fleet', 'fleet', 'A350 / 777 / 787 crews'),
    ('Narrowbody Fleet', 'fleet', 'A320 / 737 crews'),
    ('Cabin Crew', 'rank', 'All cabin crew members'),
    ('Senior Crew', 'rank', 'Senior crew discussions'),
    ('Pursers', 'rank', 'Purser-level discussions')
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 2. Layover Tips
-- ============================================================================

CREATE TABLE IF NOT EXISTS layover_tips (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    airport_code TEXT NOT NULL,
    category TEXT NOT NULL DEFAULT 'general'
        CHECK (category IN ('hotel', 'food', 'transport', 'shopping', 'sim', 'crewDiscount', 'safety', 'general')),
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    author_id UUID NOT NULL REFERENCES profiles(id),
    author_name TEXT NOT NULL,
    upvotes INT NOT NULL DEFAULT 0,
    downvotes INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_layover_tips_airport ON layover_tips(airport_code);
CREATE INDEX idx_layover_tips_category ON layover_tips(airport_code, category);
CREATE INDEX idx_layover_tips_score ON layover_tips(airport_code, (upvotes - downvotes) DESC);

-- Layover votes (one vote per user per tip)
CREATE TABLE IF NOT EXISTS layover_votes (
    tip_id UUID NOT NULL REFERENCES layover_tips(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    is_upvote BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (tip_id, user_id)
);

-- Update tip vote counts on vote
CREATE OR REPLACE FUNCTION update_tip_vote_counts()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.is_upvote THEN
            UPDATE layover_tips SET upvotes = upvotes + 1 WHERE id = NEW.tip_id;
        ELSE
            UPDATE layover_tips SET downvotes = downvotes + 1 WHERE id = NEW.tip_id;
        END IF;
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.is_upvote AND NOT NEW.is_upvote THEN
            UPDATE layover_tips SET upvotes = upvotes - 1, downvotes = downvotes + 1 WHERE id = NEW.tip_id;
        ELSIF NOT OLD.is_upvote AND NEW.is_upvote THEN
            UPDATE layover_tips SET downvotes = downvotes - 1, upvotes = upvotes + 1 WHERE id = NEW.tip_id;
        END IF;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_tip_vote_counts
    AFTER INSERT OR UPDATE ON layover_votes
    FOR EACH ROW EXECUTE FUNCTION update_tip_vote_counts();

-- RLS for layover tips
ALTER TABLE layover_tips ENABLE ROW LEVEL SECURITY;
ALTER TABLE layover_votes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tips_read" ON layover_tips FOR SELECT USING (true);
CREATE POLICY "tips_insert" ON layover_tips FOR INSERT WITH CHECK (auth.uid() = author_id);
CREATE POLICY "tips_update" ON layover_tips FOR UPDATE USING (auth.uid() = author_id);
CREATE POLICY "votes_read" ON layover_votes FOR SELECT USING (true);
CREATE POLICY "votes_upsert" ON layover_votes FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "votes_update" ON layover_votes FOR UPDATE USING (auth.uid() = user_id);

-- ============================================================================
-- 3. Shared Roster Links
-- ============================================================================

CREATE TABLE IF NOT EXISTS shared_roster_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    month_id TEXT NOT NULL,
    share_token TEXT NOT NULL UNIQUE,
    label TEXT NOT NULL DEFAULT 'Shared Roster',
    is_active BOOLEAN NOT NULL DEFAULT true,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_shared_roster_token ON shared_roster_links(share_token) WHERE is_active = true;
CREATE INDEX idx_shared_roster_user ON shared_roster_links(user_id) WHERE is_active = true;

ALTER TABLE shared_roster_links ENABLE ROW LEVEL SECURITY;

CREATE POLICY "shared_links_read_own" ON shared_roster_links FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "shared_links_read_token" ON shared_roster_links FOR SELECT USING (is_active = true);
CREATE POLICY "shared_links_insert" ON shared_roster_links FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "shared_links_update" ON shared_roster_links FOR UPDATE USING (auth.uid() = user_id);

-- ============================================================================
-- 4. Crew Flight Registry (for crew pairing lookup)
-- ============================================================================

CREATE TABLE IF NOT EXISTS crew_flight_registry (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL,
    crew_rank TEXT NOT NULL,
    flight_code TEXT NOT NULL,
    flight_date TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, flight_code, flight_date)
);

CREATE INDEX idx_crew_registry_flight ON crew_flight_registry(flight_code, flight_date);
CREATE INDEX idx_crew_registry_user ON crew_flight_registry(user_id);

ALTER TABLE crew_flight_registry ENABLE ROW LEVEL SECURITY;

CREATE POLICY "registry_read" ON crew_flight_registry FOR SELECT USING (true);
CREATE POLICY "registry_upsert" ON crew_flight_registry FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "registry_update" ON crew_flight_registry FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "registry_delete" ON crew_flight_registry FOR DELETE USING (auth.uid() = user_id);

-- ============================================================================
-- 5. Performance indexes for existing tables
-- ============================================================================

-- Improve swap listing queries for high load
CREATE INDEX IF NOT EXISTS idx_swap_listings_status_date ON swap_listings(status, flight_date);
CREATE INDEX IF NOT EXISTS idx_swap_listings_posted_by ON swap_listings(posted_by);

-- Improve conversation lookup
CREATE INDEX IF NOT EXISTS idx_conversations_participants ON conversations(initiator_id, listing_owner_id);
CREATE INDEX IF NOT EXISTS idx_conversations_listing ON conversations(listing_id);

-- Improve message retrieval
CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id, sent_at);
