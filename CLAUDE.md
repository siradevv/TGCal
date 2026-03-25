# TGCal - Project Notes for Claude

## What This App Does
TGCal is an iOS app for Thai Airways crew members that converts roster PDF documents into iPhone calendar events. Users import their PDF roster, the app uses OCR to extract flight data, looks up live flight info, and adds everything to the device calendar. It also calculates monthly earnings based on pay-per-block (PPB) rates.

- **Target users**: Thai Airways pilots and flight attendants
- **Bundle ID**: `com.sira.TGCal`
- **iOS Target**: 18.5
- **GitHub account**: siradevv (default)
- **All timezones**: Hard-coded to Asia/Bangkok for roster calculations

## Project Structure
```
TGCal/
├── TGCalApp.swift                  # Entry point, splash screen
├── TGCalStore.swift                # Central state + JSON persistence
├── RootTabView.swift               # Tab navigation (Overview, Flights, Settings)
├── Models.swift                    # Core types: FlightEventDraft, RosterMonthRecord, OCRResult, etc.
├── ContentView.swift               # Flights list, PDF import, calendar logic
├── OverviewView.swift              # Dashboard with next flight briefing card
├── SettingsView.swift              # App settings
├── EarningsView.swift              # Monthly earnings breakdown
├── PrivacyPolicyView.swift         # In-app privacy policy
├── EditFlightView.swift            # Flight detail editor
├── StyledRosterView.swift          # Roster calendar view
├── NextFlightBriefingCard.swift    # Next flight info card
├── TGNoRosterHeroCard.swift        # Empty state card
├── TGComponents.swift              # Shared UI theme & components (indigo/rose/mint)
├── OCRService.swift                # Vision framework text recognition from PDF images
├── RosterParser.swift              # Parses OCR text → flight objects with confidence scoring
├── FlightNumberRosterParser.swift  # Additional flight number parsing
├── CalendarService.swift           # EventKit: creates/updates calendar events
├── AviationstackService.swift      # Live flight data API (cached)
├── AviationstackConfiguration.swift # API key management
├── WeatherService.swift            # Open-Meteo weather API (actor-based)
├── CurrencyExchangeService.swift   # Currency conversion
├── ScheduleSlipService.swift       # PDF roster parsing engine (see "PDF Parsing" section below)
├── BriefingNotesStore.swift        # Briefing notes persistence
├── EarningsCalculator.swift        # PPB earnings computation
├── EarningsModels.swift            # Earnings data structures
├── EarningsRates.json              # Pay-per-block rate tables (summer/winter)
├── AirportDirectory.swift          # Airport code references
├── DestinationMetadata.swift       # Weather/location data by airport
└── Assets.xcassets/
```

## Architecture
**Pattern**: SwiftUI + MVVM-inspired with a central Store
- `TGCalStore` is the single source of truth — holds all roster months and flight records, persists to JSON in Application Support
- Services are independent actors/classes for each concern
- Views read from the store and call services directly
- No external Swift packages — all native frameworks only

## Frameworks & APIs
**Native**: SwiftUI, EventKit, Vision, PDFKit, CoreImage, CoreGraphics, UIKit
**External APIs**:
- **Aviationstack** — live flight lookups (requires API key in `AviationstackSecrets.plist`, not in git — use `AviationstackSecrets.template.plist` as reference)
- **Open-Meteo** — weather forecasts (free, no key needed)

## Key Behaviours
- **Calendar deduplication**: Events tagged with "Imported by TGCal" to avoid duplicates
- **Earnings**: Calculated from `EarningsRates.json` with separate summer/winter season rates

## PDF Parsing (ScheduleSlipService.swift)
This is the most critical and complex part of the app. It extracts flight and duty data from Thai Airways crew roster PDFs. **Parsing accuracy is an ongoing effort** — each new roster PDF (monthly) is a chance to discover edge cases and improve.

### How it works
1. **PDFKit token extraction** (`extractPDFTokens`) — extracts every text token with its (x, y) bounding box position
2. **Day header detection** (`extractPDFDayHeaders`) — finds "1WED", "2THU" etc. to build x-position → day mapping
3. **FLT/DEP/ARR block parsing** (`parseFlightDetailsFromPDFPage`) — finds FLT/DEP/ARR label rows, then for each block:
   - Matches flight numbers to origins, destinations, dep/arr times using **x-proximity** (NOT array index)
   - Detects duty codes (TRG, SBY, etc.) — alphabetic tokens in FLT row with no nearby airport
4. **OCR fallback** — renders page as image, runs Vision OCR, merges results to fill gaps
5. **Sanitization** (`sanitizeDutyEntries`) — removes false-positive duty codes that match airport codes used in actual flights

### PDF layout (Thai Airways roster)
The roster has TWO data areas stacked vertically:
- **DUTY area** (above FLT row): compact vertical columns per day with flight numbers, airports, duty codes, and times
- **FLT/DEP/ARR bands** (below): standard horizontal bands with FLT labels, DEP origins/times, ARR destinations/times
- Duty codes (TRG, SBY) have times in the DUTY area but NOT in the DEP/ARR bands
- Multi-session duties (e.g. morning + afternoon TRG) span multiple FLT blocks — times are merged into a combined range

### Key parsing rules
- Flight numbers must be ≥ 10 (rejects stray single-digit OCR artifacts)
- Duty key format: `__DUTY_{day}_{code}` — when split by `_` (omitting empty), day is at index 1
- x-proximity matching: dep within 15px, arr within max(20px, 1.5× column width) for overnight flights
- Duty code times: search DEP/ARR bands first, fall back to DUTY area above FLT row (y > fltMidY + 8)

### Testing PDF parsing changes
- **Test PDFs** are in `~/Desktop/roster/` — April.pdf, individual-report.pdf (March), report2.pdf (February)
- Write a standalone Swift script using PDFKit to extract tokens and verify parsing without needing the simulator
- Always test ALL available PDFs after making parsing changes to catch regressions
- All fixes must be **universal** — they should improve accuracy for all rosters, not just a specific month

## Persistence
- File: `~/Library/Application Support/TGCal/tgcal_store.json`
- Format: JSON via `Codable` (`TGCalStoreState` → array of `RosterMonthRecord`)

## Important Notes
- **Secrets**: `AviationstackSecrets.plist` is gitignored — never commit it
- **Permissions required**: Full calendar access (`NSCalendarsFullAccessUsageDescription`)
- **Orientation**: Portrait only
- **App Store**: Live — privacy policy at `https://siradevv.github.io/TGCal/AppStore/privacy-policy.html`
- **Support contact**: tgcal.app@gmail.com
- Submission docs in `AppStore/AppStoreConnect-Submission.md`
