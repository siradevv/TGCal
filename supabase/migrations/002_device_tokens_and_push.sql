-- ============================================================
-- Device Tokens for APNs Push Notifications
-- ============================================================

-- Enable pg_net for HTTP calls from triggers
create extension if not exists pg_net with schema extensions;

create table public.device_tokens (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles(id) on delete cascade,
    token text not null,
    platform text not null default 'ios' check (platform in ('ios')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    -- One token per device per user
    unique (user_id, token)
);

create index idx_device_tokens_user on public.device_tokens(user_id);

alter table public.device_tokens enable row level security;

create policy "Users can view their own tokens"
    on public.device_tokens for select
    to authenticated
    using (auth.uid() = user_id);

create policy "Users can insert their own tokens"
    on public.device_tokens for insert
    to authenticated
    with check (auth.uid() = user_id);

create policy "Users can update their own tokens"
    on public.device_tokens for update
    to authenticated
    using (auth.uid() = user_id);

create policy "Users can delete their own tokens"
    on public.device_tokens for delete
    to authenticated
    using (auth.uid() = user_id);

-- Updated_at trigger
create trigger set_updated_at before update on public.device_tokens
    for each row execute procedure public.update_updated_at();

-- ============================================================
-- Push notification helper: enqueue a push via Edge Function
-- ============================================================

-- This function is called by triggers to send push notifications.
-- It posts to the Supabase Edge Function `send-push`.
-- Set the SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY as needed.

create or replace function public.send_push_notification(
    p_recipient_id uuid,
    p_title text,
    p_body text,
    p_data jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
as $$
declare
    v_url text;
    v_service_key text;
begin
    -- Read project config from vault or use env
    -- These should be set via: select vault.create_secret('supabase_url', 'https://YOUR_PROJECT.supabase.co');
    -- For now, use current_setting which can be set per-project
    v_url := current_setting('app.settings.supabase_url', true);
    v_service_key := current_setting('app.settings.supabase_service_role_key', true);

    -- If not configured, skip silently
    if v_url is null or v_service_key is null then
        return;
    end if;

    perform net.http_post(
        url := v_url || '/functions/v1/send-push',
        body := jsonb_build_object(
            'recipient_id', p_recipient_id,
            'title', p_title,
            'body', p_body,
            'data', p_data
        )::text,
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || v_service_key
        )::jsonb
    );
end;
$$;

-- ============================================================
-- Trigger: notify listing owner on new conversation
-- ============================================================

create or replace function public.notify_new_conversation()
returns trigger
language plpgsql
security definer
as $$
declare
    v_initiator_name text;
    v_flight_code text;
begin
    -- Look up the initiator's name
    select display_name into v_initiator_name
    from public.profiles
    where id = new.initiator_id;

    -- Look up the flight code
    select flight_code into v_flight_code
    from public.swap_listings
    where id = new.listing_id;

    -- Notify the listing owner
    perform public.send_push_notification(
        new.listing_owner_id,
        'New Swap Interest',
        coalesce(v_initiator_name, 'Someone') || ' wants to swap ' || coalesce(v_flight_code, 'a flight') || ' with you.',
        jsonb_build_object('type', 'new_conversation', 'conversation_id', new.id)
    );

    return new;
end;
$$;

create trigger on_new_conversation
    after insert on public.conversations
    for each row execute procedure public.notify_new_conversation();

-- ============================================================
-- Trigger: notify recipient on new message
-- ============================================================

create or replace function public.notify_new_message()
returns trigger
language plpgsql
security definer
as $$
declare
    v_sender_name text;
    v_recipient_id uuid;
    v_conv record;
begin
    -- Look up the sender's name
    select display_name into v_sender_name
    from public.profiles
    where id = new.sender_id;

    -- Look up the conversation to find the other participant
    select * into v_conv
    from public.conversations
    where id = new.conversation_id;

    -- Determine recipient (the participant who is NOT the sender)
    if new.sender_id = v_conv.initiator_id then
        v_recipient_id := v_conv.listing_owner_id;
    else
        v_recipient_id := v_conv.initiator_id;
    end if;

    -- Send push to recipient
    perform public.send_push_notification(
        v_recipient_id,
        coalesce(v_sender_name, 'Crew Member'),
        left(new.text, 200),
        jsonb_build_object('type', 'new_message', 'conversation_id', new.conversation_id)
    );

    return new;
end;
$$;

create trigger on_new_message
    after insert on public.messages
    for each row execute procedure public.notify_new_message();

-- ============================================================
-- Trigger: notify on swap confirmation or cancellation
-- ============================================================

create or replace function public.notify_conversation_status_change()
returns trigger
language plpgsql
security definer
as $$
declare
    v_flight_code text;
    v_initiator_name text;
    v_owner_name text;
begin
    -- Only fire when status actually changes
    if old.status = new.status then
        return new;
    end if;

    -- Look up flight code
    select flight_code into v_flight_code
    from public.swap_listings
    where id = new.listing_id;

    -- Look up names
    select display_name into v_initiator_name
    from public.profiles where id = new.initiator_id;

    select display_name into v_owner_name
    from public.profiles where id = new.listing_owner_id;

    if new.status = 'confirmed' then
        -- Notify both parties
        perform public.send_push_notification(
            new.initiator_id,
            'Swap Confirmed',
            coalesce(v_flight_code, 'Flight') || ' swap with ' || coalesce(v_owner_name, 'crew member') || ' is confirmed.',
            jsonb_build_object('type', 'swap_confirmed', 'conversation_id', new.id)
        );
        perform public.send_push_notification(
            new.listing_owner_id,
            'Swap Confirmed',
            coalesce(v_flight_code, 'Flight') || ' swap with ' || coalesce(v_initiator_name, 'crew member') || ' is confirmed.',
            jsonb_build_object('type', 'swap_confirmed', 'conversation_id', new.id)
        );

    elsif new.status = 'cancelled' and old.status = 'confirmed' then
        -- Notify both parties of cancellation
        perform public.send_push_notification(
            new.initiator_id,
            'Swap Cancelled',
            coalesce(v_flight_code, 'Flight') || ' swap has been cancelled.',
            jsonb_build_object('type', 'swap_cancelled', 'conversation_id', new.id)
        );
        perform public.send_push_notification(
            new.listing_owner_id,
            'Swap Cancelled',
            coalesce(v_flight_code, 'Flight') || ' swap has been cancelled.',
            jsonb_build_object('type', 'swap_cancelled', 'conversation_id', new.id)
        );
    end if;

    return new;
end;
$$;

create trigger on_conversation_status_change
    after update on public.conversations
    for each row execute procedure public.notify_conversation_status_change();
