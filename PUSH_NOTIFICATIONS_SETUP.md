# Push Notifications Setup (APNs)

## Overview

TGCal uses Apple Push Notification service (APNs) to deliver real-time notifications
when the app is closed. Notifications are triggered by database events (new message,
new conversation, swap confirmed/cancelled) via Supabase Edge Functions.

## Architecture

```
User Action → Supabase DB Insert/Update
                    ↓
            PostgreSQL Trigger
                    ↓
            pg_net HTTP POST → Edge Function (send-push)
                    ↓
            APNs HTTP/2 API
                    ↓
            Recipient's iPhone
```

## Step-by-Step Setup

### 1. Apple Developer Portal

1. Go to [developer.apple.com](https://developer.apple.com) → Certificates, Identifiers & Profiles
2. Under **Keys**, create a new key:
   - Name: "TGCal Push"
   - Enable **Apple Push Notifications service (APNs)**
   - Download the `.p8` file — you can only download it ONCE
3. Note down:
   - **Key ID** (10-character string, e.g. `ABC123DEFG`)
   - **Team ID** (found in Membership tab)

### 2. Xcode Configuration

1. Open `TGCal.xcodeproj` in Xcode
2. Select the TGCal target → **Signing & Capabilities**
3. Click **+ Capability** → add **Push Notifications**
4. Ensure `TGCal.entitlements` has the `aps-environment` key
   - Use `development` for debug builds
   - Change to `production` for App Store / TestFlight builds

### 3. Supabase Secrets

Set these secrets in your Supabase project dashboard (Settings → Edge Functions → Secrets),
or via the CLI:

```bash
supabase secrets set APNS_KEY_ID="YOUR_KEY_ID"
supabase secrets set APNS_TEAM_ID="YOUR_TEAM_ID"
supabase secrets set APNS_TOPIC="com.yourcompany.TGCal"
supabase secrets set APNS_ENVIRONMENT="development"   # or "production"
supabase secrets set APNS_PRIVATE_KEY="$(cat AuthKey_XXXXXXXX.p8)"
```

### 4. Database Configuration

Set the app settings so the DB triggers can call the Edge Function:

```sql
-- Run in Supabase SQL Editor
ALTER DATABASE postgres SET app.settings.supabase_url = 'https://YOUR_PROJECT.supabase.co';
ALTER DATABASE postgres SET app.settings.supabase_service_role_key = 'YOUR_SERVICE_ROLE_KEY';
```

### 5. Deploy the Edge Function

```bash
cd supabase
supabase functions deploy send-push
```

### 6. Run the Migration

```bash
supabase db push
```

This applies `002_device_tokens_and_push.sql` which creates:
- `device_tokens` table
- `send_push_notification()` helper function
- Triggers on `conversations`, `messages` for automatic push delivery

## Testing

1. Build and run TGCal on a **physical device** (push doesn't work on Simulator)
2. Sign in — the app will register for push and store the device token
3. Have another user (or use a second device) send a message
4. You should receive a push notification even when the app is backgrounded

## What Gets Notified

| Event                   | Recipient        | Title              |
|-------------------------|------------------|--------------------|
| New conversation        | Listing owner    | "New Swap Interest" |
| New message             | Other party      | Sender's name      |
| Swap confirmed (both)   | Both parties     | "Swap Confirmed"   |
| Swap cancelled          | Both parties     | "Swap Cancelled"   |

## Switching to Production

1. Update `APNS_ENVIRONMENT` secret to `production`
2. Update `TGCal.entitlements` → `aps-environment` to `production`
3. Archive and upload to App Store Connect
