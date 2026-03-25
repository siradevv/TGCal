-- ============================================================
-- TGCal Flight Swap Schema
-- ============================================================

-- Profiles (extends Supabase auth.users)
create table public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    display_name text not null,
    crew_rank text not null default 'cabin' check (crew_rank in ('cabin', 'senior', 'purser')),
    avatar_url text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Profiles are viewable by authenticated users"
    on public.profiles for select
    to authenticated
    using (true);

create policy "Users can update their own profile"
    on public.profiles for update
    to authenticated
    using (auth.uid() = id);

create policy "Users can insert their own profile"
    on public.profiles for insert
    to authenticated
    with check (auth.uid() = id);

-- Auto-create profile on signup
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
    insert into public.profiles (id, display_name)
    values (
        new.id,
        coalesce(new.raw_user_meta_data ->> 'display_name', 'Crew Member')
    );
    return new;
end;
$$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute procedure public.handle_new_user();

-- ============================================================
-- Swap Listings
-- ============================================================

create type swap_status as enum ('open', 'pending', 'confirmed', 'cancelled');

create table public.swap_listings (
    id uuid primary key default gen_random_uuid(),
    posted_by uuid not null references public.profiles(id) on delete cascade,
    posted_by_name text not null,
    flight_code text not null,
    origin text not null,
    destination text not null,
    flight_date date not null,
    departure_time text,
    note text,
    status swap_status not null default 'open',
    matched_with uuid references public.profiles(id),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index idx_swap_listings_status on public.swap_listings(status);
create index idx_swap_listings_flight_date on public.swap_listings(flight_date);
create index idx_swap_listings_destination on public.swap_listings(destination);
create index idx_swap_listings_posted_by on public.swap_listings(posted_by);

alter table public.swap_listings enable row level security;

create policy "Swap listings are viewable by authenticated users"
    on public.swap_listings for select
    to authenticated
    using (true);

create policy "Users can create their own listings"
    on public.swap_listings for insert
    to authenticated
    with check (auth.uid() = posted_by);

create policy "Users can update their own listings"
    on public.swap_listings for update
    to authenticated
    using (auth.uid() = posted_by or auth.uid() = matched_with);

create policy "Users can delete their own listings"
    on public.swap_listings for delete
    to authenticated
    using (auth.uid() = posted_by);

-- ============================================================
-- Conversations
-- ============================================================

create type conversation_status as enum ('active', 'confirmed', 'cancelled');

create table public.conversations (
    id uuid primary key default gen_random_uuid(),
    listing_id uuid not null references public.swap_listings(id) on delete cascade,
    initiator_id uuid not null references public.profiles(id),
    listing_owner_id uuid not null references public.profiles(id),
    status conversation_status not null default 'active',
    initiator_confirmed boolean not null default false,
    owner_confirmed boolean not null default false,
    last_message text,
    last_message_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    -- Prevent duplicate conversations for same listing + initiator
    unique (listing_id, initiator_id)
);

create index idx_conversations_initiator on public.conversations(initiator_id);
create index idx_conversations_owner on public.conversations(listing_owner_id);
create index idx_conversations_listing on public.conversations(listing_id);

alter table public.conversations enable row level security;

create policy "Users can view their own conversations"
    on public.conversations for select
    to authenticated
    using (auth.uid() = initiator_id or auth.uid() = listing_owner_id);

create policy "Authenticated users can create conversations"
    on public.conversations for insert
    to authenticated
    with check (auth.uid() = initiator_id);

create policy "Participants can update conversations"
    on public.conversations for update
    to authenticated
    using (auth.uid() = initiator_id or auth.uid() = listing_owner_id);

-- ============================================================
-- Messages
-- ============================================================

create table public.messages (
    id uuid primary key default gen_random_uuid(),
    conversation_id uuid not null references public.conversations(id) on delete cascade,
    sender_id uuid not null references public.profiles(id),
    text text not null,
    is_read boolean not null default false,
    sent_at timestamptz not null default now()
);

create index idx_messages_conversation on public.messages(conversation_id, sent_at);
create index idx_messages_sender on public.messages(sender_id);

alter table public.messages enable row level security;

create policy "Participants can view messages"
    on public.messages for select
    to authenticated
    using (
        exists (
            select 1 from public.conversations c
            where c.id = conversation_id
            and (auth.uid() = c.initiator_id or auth.uid() = c.listing_owner_id)
        )
    );

create policy "Participants can send messages"
    on public.messages for insert
    to authenticated
    with check (
        auth.uid() = sender_id
        and exists (
            select 1 from public.conversations c
            where c.id = conversation_id
            and (auth.uid() = c.initiator_id or auth.uid() = c.listing_owner_id)
        )
    );

create policy "Sender can update their own messages"
    on public.messages for update
    to authenticated
    using (auth.uid() = sender_id);

-- ============================================================
-- Enable realtime for messages and conversations
-- ============================================================

alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.conversations;
alter publication supabase_realtime add table public.swap_listings;

-- ============================================================
-- Updated_at triggers
-- ============================================================

create or replace function public.update_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create trigger set_updated_at before update on public.profiles
    for each row execute procedure public.update_updated_at();

create trigger set_updated_at before update on public.swap_listings
    for each row execute procedure public.update_updated_at();

create trigger set_updated_at before update on public.conversations
    for each row execute procedure public.update_updated_at();
