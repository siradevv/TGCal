# TGCal Improvement Plan

## Overview

Four new features to add, plus a migration away from Aviationstack to a more cost-effective flight data provider.

---

## 1. iOS Home Screen Widget — "Next Flight"

### What
A small/medium WidgetKit widget showing the crew member's next upcoming flight at a glance.

### Why
Crew check their next duty constantly. A widget saves opening the app every time — it's the single highest-frequency interaction.

### Design

**Small Widget (2×2):**
```
┌─────────────────┐
│  TG 971         │
│  BKK → NRT      │
│  14:30 dep      │
│  Tomorrow       │
└─────────────────┘
```

**Medium Widget (4×2):**
```
┌───────────────────────────────┐
│  ✈ TG 971          Tomorrow  │
│  BKK → NRT                   │
│  Dep 14:30    Arr 22:30 +1   │
│  Narita, Japan 🇯🇵            │
└───────────────────────────────┘
```

### Technical Approach

1. **Create a new Widget Extension target** (`TGCalWidget`)
2. **Shared data via App Group:**
   - Add an App Group capability (e.g., `group.com.tgcal.shared`) to both the main app and widget
   - Modify `TGCalStore.saveToDisk()` to also write a lightweight `next_flight.json` to the shared App Group container
   - Widget reads from this shared file
3. **Timeline Provider:**
   - `getTimeline()` reads the shared JSON, finds next flight by comparing dates
   - Schedule timeline refresh every 30 minutes and after each roster import
   - Use `WidgetCenter.shared.reloadAllTimelines()` in the main app after store changes
4. **Widget Views:**
   - `SmallWidgetView` — flight number, route, departure time, relative date
   - `MediumWidgetView` — adds arrival time, destination city name, flag
   - Use existing `DestinationMeta` for city names and flags
5. **Deep link:** Tap widget → opens app to Overview tab

### Files to Create/Modify

| File | Action |
|---|---|
| `TGCalWidget/` (new extension target) | Create |
| `TGCalWidget/TGCalWidget.swift` | Widget entry point, timeline provider |
| `TGCalWidget/SmallWidgetView.swift` | Small widget layout |
| `TGCalWidget/MediumWidgetView.swift` | Medium widget layout |
| `TGCalWidget/NextFlightEntry.swift` | Timeline entry model |
| `TGCal/TGCalStore.swift` | Add shared container write |
| `TGCal/Models.swift` | Extract `NextFlightSnapshot` codable struct |
| `TGCal.xcodeproj` | Add widget target + App Group |

### Estimated Complexity
Medium — WidgetKit is straightforward, main work is data sharing via App Group.

---

## 2. Push Notifications (Duty Reminders + Flight Status)

### What
Local notifications for upcoming duties, plus optional flight status alerts.

### Why
Crew need reliable reminders before report time. Flight status changes (delays, gate changes) are critical during duty.

### Design

**Notification Types:**

| Type | Trigger | Content |
|---|---|---|
| Duty Reminder (12h) | 12 hours before departure | "TG 971 BKK→NRT departs tomorrow at 14:30" |
| Duty Reminder (3h) | 3 hours before departure | "TG 971 BKK→NRT departs in 3 hours" |
| Roster Imported | After successful parse | "March 2026 roster imported — 18 flights" |

### Technical Approach

1. **Use `UNUserNotificationCenter`** (local notifications, no server needed)
2. **Create `NotificationService.swift`:**
   - `scheduleReminders(for month: RosterMonthRecord)` — schedules 12h and 3h reminders for all flights
   - `cancelReminders(for monthId: String)` — clears old notifications when re-importing
   - `requestPermission()` — called on first roster import
3. **Notification scheduling:**
   - After each roster import/update, cancel existing notifications for that month and reschedule
   - Use `UNCalendarNotificationTrigger` with Bangkok timezone date components
   - Limit: iOS allows 64 pending notifications — prioritize nearest flights
4. **Settings integration:**
   - Add toggle in SettingsView: "Duty Reminders" (on/off)
   - Add picker: reminder intervals (3h, 6h, 12h, 24h) — multi-select
   - Persist preferences in UserDefaults
5. **Flight status alerts (future):**
   - This depends on the flight API migration (see section below)
   - Once we have a cost-effective API, add background fetch to check for delays
   - Use `BGAppRefreshTask` to poll flight status periodically on duty days

### Files to Create/Modify

| File | Action |
|---|---|
| `TGCal/NotificationService.swift` | Create — scheduling logic |
| `TGCal/SettingsView.swift` | Add reminder toggles |
| `TGCal/TGCalStore.swift` | Trigger notification scheduling on upsertMonth |
| `TGCal/TGCalApp.swift` | Request notification permission |
| `Info.plist` | Add background modes if needed |

### Estimated Complexity
Low-Medium — local notifications are well-documented; flight status polling adds complexity later.

---

## 3. Historical Analytics / Logbook

### What
A new "Logbook" tab showing flight hours, destinations visited, and earnings trends over time.

### Why
Crew want to see their career stats. This data already exists in the store — we just need to visualize it.

### Design

**Logbook Tab Layout:**

```
┌─ Logbook ─────────────────────┐
│                               │
│  Total Flights: 847           │
│  Total Block Hours: 2,341h    │
│  Countries Visited: 28        │
│                               │
│  ── Flight Hours ──────────── │
│  [Bar chart: hours per month] │
│                               │
│  ── Earnings ──────────────── │
│  [Line chart: THB per month]  │
│                               │
│  ── Top Destinations ──────── │
│  1. NRT  Narita      ██████ 47│
│  2. HND  Haneda      █████  38│
│  3. LHR  London      ████   29│
│  4. CDG  Paris       ███    22│
│  5. SIN  Singapore   ███    21│
│                               │
│  ── Destinations Map ──────── │
│  [World map with pins]        │
│                               │
└───────────────────────────────┘
```

### Technical Approach

1. **Use Swift Charts** (iOS 16+ framework) for graphs
2. **Create `LogbookView.swift`** as a new tab in `RootTabView`
3. **Aggregate data from `TGCalStore.months`:**
   - All calculations derived from existing `RosterMonthRecord` data
   - No new data storage needed
4. **Components:**
   - `LogbookStatsCard` — lifetime totals (flights, hours, countries)
   - `FlightHoursChart` — bar chart of block hours per month (Swift Charts `BarMark`)
   - `EarningsChart` — line chart of monthly earnings (Swift Charts `LineMark`)
   - `TopDestinationsView` — ranked bar list with visit counts
   - `DestinationMapView` — `Map` with `Annotation` pins at each destination (using coordinates from `DestinationMeta`)
5. **Data aggregation** in `LogbookViewModel.swift`:
   - `totalFlights()` — sum of all flights across all months
   - `totalBlockHours()` — sum of flight durations (reuse `blockMinutes()` from OverviewView)
   - `monthlyHours()` — array of (monthId, hours) for charting
   - `monthlyEarnings()` — array of (monthId, THB) using EarningsCalculator
   - `destinationRanking()` — aggregate visits across all months
   - `uniqueCountries()` — distinct countries from DestinationMeta

### Files to Create/Modify

| File | Action |
|---|---|
| `TGCal/LogbookView.swift` | Create — main logbook tab |
| `TGCal/LogbookViewModel.swift` | Create — data aggregation |
| `TGCal/FlightHoursChart.swift` | Create — bar chart component |
| `TGCal/EarningsChart.swift` | Create — line chart component |
| `TGCal/TopDestinationsView.swift` | Create — destination ranking |
| `TGCal/DestinationMapView.swift` | Create — map with pins |
| `TGCal/RootTabView.swift` | Add Logbook tab |
| `TGCal/DestinationMeta.swift` | Add lat/lon coordinates for map pins |

### Estimated Complexity
Medium — Swift Charts makes graphing easy; map pins need coordinate data added to DestinationMeta.

---

## 4. Export Earnings to PDF / CSV

### What
Generate a clean monthly earnings report that crew can save, print, or share.

### Why
Crew need earnings records for Thai tax filing and bank loan applications. A professional PDF export from the app saves manual bookkeeping.

### Design

**PDF Report Layout:**
```
┌─────────────────────────────────────┐
│         TGCal Earnings Report       │
│         March 2026                  │
│─────────────────────────────────────│
│ Flight     Count    PPB     Total   │
│─────────────────────────────────────│
│ TG 971       2    3,200    6,400    │
│ TG 972       2    3,200    6,400    │
│ TG 623       1    2,800    2,800    │
│ TG 624       1    2,800    2,800    │
│ ...                                 │
│─────────────────────────────────────│
│ TOTAL               ฿ 142,600      │
│                                     │
│ Season: Summer 2026                 │
│ Total Flights: 18                   │
│ Generated by TGCal                  │
└─────────────────────────────────────┘
```

### Technical Approach

1. **PDF generation** using `UIGraphicsPDFRenderer` (native, no dependencies)
2. **CSV generation** using simple string building
3. **Create `EarningsExportService.swift`:**
   - `generatePDF(for result: MonthEarningsResult, month: RosterMonthRecord) -> Data`
   - `generateCSV(for result: MonthEarningsResult, month: RosterMonthRecord) -> Data`
4. **PDF layout:**
   - A4 page size (595 × 842 points)
   - Header with app name, month, season
   - Table with columns: Flight, Count, PPB (฿), Subtotal (฿)
   - Footer with total, flight count, generation date
   - Use Core Text for precise text placement
5. **Share integration:**
   - Add "Export" button in the earnings section of OverviewView
   - Present `ShareLink` or `UIActivityViewController` with the generated file
   - Support both PDF and CSV via an action sheet picker
6. **CSV format:**
   ```
   Flight,Count,PPB (THB),Subtotal (THB)
   TG 971,2,3200,6400
   TG 972,2,3200,6400
   ...
   TOTAL,18,,142600
   ```

### Files to Create/Modify

| File | Action |
|---|---|
| `TGCal/EarningsExportService.swift` | Create — PDF + CSV generation |
| `TGCal/OverviewView.swift` | Add export button to earnings card |
| `TGCal/EarningsExportButton.swift` | Create — share sheet trigger component |

### Estimated Complexity
Low-Medium — `UIGraphicsPDFRenderer` handles the heavy lifting; CSV is trivial.

---

## 5. Flight Data API Migration (Aviationstack Alternative)

### Problem
Aviationstack is expensive for individual/small-app use. The free tier is very limited (100 requests/month) and paid plans start at $50/month.

### Recommended Alternatives

| Service | Free Tier | Paid | Pros | Cons |
|---|---|---|---|---|
| **AeroDataBox** (via RapidAPI) | 150 req/month | $10/mo (5K req) | Flight status, schedules, aircraft info. Good accuracy. | RapidAPI middleman |
| **FlightAware AeroAPI** | Limited trial | Pay-per-query (~$0.01/query) | Industry standard, very accurate | No true free tier |
| **AviationEdge** | 100 req/month | $15/mo (5K req) | Similar to Aviationstack, cheaper | Similar data quality |
| **OpenSky Network** | Unlimited | Free | Real-time tracking, open data | No schedules/gates, only live positions |
| **FlightRadar24 API** | N/A | Enterprise only | Best data | Not available for small apps |

### Recommendation: **AeroDataBox via RapidAPI**

**Why:**
- Best price/quality ratio for a small app
- 150 free requests/month (enough for personal use testing)
- $10/month gets 5,000 requests (more than enough)
- Provides: flight status, departure/arrival gates, aircraft type, delays
- REST API, easy to integrate

### Migration Plan

1. **Create `FlightDataService` protocol:**
   ```swift
   protocol FlightDataService {
       func fetchFlightDetails(flightCode: String, date: Date, origin: String, destination: String) async throws -> LiveFlightDetails
       func checkConnection() async -> ConnectionStatus
   }
   ```
2. **Implement `AeroDataBoxService`** conforming to the protocol
3. **Keep `AviationstackService`** as a fallback (refactored to conform to same protocol)
4. **Add provider picker in Settings** — let user choose their preferred API + enter key
5. **Update caching logic** — same cache structure works for any provider

### Files to Create/Modify

| File | Action |
|---|---|
| `TGCal/FlightDataService.swift` | Create — protocol definition |
| `TGCal/AeroDataBoxService.swift` | Create — new provider |
| `TGCal/AviationstackService.swift` | Refactor to conform to protocol |
| `TGCal/SettingsView.swift` | Add API provider picker |

---

## 6. Code Quality Improvements (Do Alongside Features)

These should be addressed as we build the new features:

### 6a. Split ContentView
Extract the PDF import logic and parsing into a dedicated `RosterImportViewModel`. The view should only handle layout.

### 6b. Add API Retry Logic
Create a shared `APIClient` utility with exponential backoff (3 retries, 1s/2s/4s delays). Use it in WeatherService, CurrencyExchangeService, and the new FlightDataService.

### 6c. Add Structured Logging
Use `os.Logger` with subsystems:
- `com.tgcal.ocr` — PDF parsing
- `com.tgcal.api` — external API calls
- `com.tgcal.calendar` — EventKit operations
- `com.tgcal.store` — data persistence

### 6d. CalendarService Tests
Write unit tests with a mock EventStore to verify:
- Event creation with correct timezone
- Duplicate detection
- Removal of previously imported events

---

## Implementation Order

| Phase | Feature | Dependencies |
|---|---|---|
| 1 | Export Earnings (PDF/CSV) | None — standalone, quick win |
| 2 | Historical Analytics / Logbook | None — reads existing data |
| 3 | iOS Widget | Needs App Group setup |
| 4 | Push Notifications | Needs UNUserNotificationCenter |
| 5 | Flight API Migration | Can be done anytime independently |

Phase 1 and 2 can be built in parallel. Phase 3 and 4 can also be parallel.

---

## Summary

| Feature | New Files | Modified Files | Complexity |
|---|---|---|---|
| Widget | 5 | 3 | Medium |
| Notifications | 2 | 3 | Low-Medium |
| Logbook | 7 | 2 | Medium |
| Export | 2 | 1 | Low-Medium |
| API Migration | 3 | 2 | Medium |
| **Total** | **19** | **11** | — |
