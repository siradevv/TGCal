-- ============================================================
-- Security hardening for swap tables and messages
-- ============================================================

-- Fix #30: Add ON DELETE SET NULL to matched_with FK
alter table public.swap_listings
    drop constraint if exists swap_listings_matched_with_fkey;
alter table public.swap_listings
    add constraint swap_listings_matched_with_fkey
    foreign key (matched_with) references public.profiles(id)
    on delete set null;

-- Fix #32-33: Replace overly permissive UPDATE policy on swap_listings
-- with separate policies for owner and matched user
drop policy if exists "Users can update their own listings" on public.swap_listings;

create policy "Owners can update their own listings"
    on public.swap_listings for update
    to authenticated
    using (auth.uid() = posted_by)
    with check (auth.uid() = posted_by);

create policy "Matched users can update listing status only"
    on public.swap_listings for update
    to authenticated
    using (auth.uid() = matched_with)
    with check (
        auth.uid() = matched_with
        and posted_by = posted_by  -- prevent changing owner
        and flight_code = flight_code  -- prevent changing flight
        and flight_date = flight_date  -- prevent changing date
    );

-- Fix #34: Replace overly broad message UPDATE policy
-- Only allow updating is_read field
drop policy if exists "Sender can update their own messages" on public.messages;

create policy "Recipients can mark messages as read"
    on public.messages for update
    to authenticated
    using (
        exists (
            select 1 from public.conversations c
            where c.id = conversation_id
            and (auth.uid() = c.initiator_id or auth.uid() = c.listing_owner_id)
        )
    )
    with check (
        sender_id = sender_id  -- prevent changing sender
        and conversation_id = conversation_id  -- prevent moving messages
        and text = text  -- prevent editing text
    );

-- Fix #37: Add text length constraints
alter table public.profiles
    add constraint profiles_display_name_length
    check (length(display_name) <= 100);

alter table public.swap_listings
    add constraint swap_listings_flight_code_length
    check (length(flight_code) <= 20);

alter table public.swap_listings
    add constraint swap_listings_note_length
    check (length(note) <= 500);

alter table public.messages
    add constraint messages_text_length
    check (length(text) <= 5000);
