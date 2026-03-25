import SwiftUI
import UniformTypeIdentifiers

/// The new home tab — a proper month-grid calendar showing flights, duties, swaps, and alerts.
struct CalendarTabView: View {
    @EnvironmentObject private var store: TGCalStore
    @ObservedObject private var alertService = FlightAlertService.shared
    @ObservedObject private var offlineCache = OfflineCacheService.shared

    @State private var displayedMonth: Date = Date()
    @State private var selectedDay: CalendarDayEvents?
    @State private var isShowingPDFImporter = false
    @State private var isProcessingSchedule = false
    @State private var alertContext: CalendarAlertContext?
    @State private var isMonthStatsExpanded = false

    @Binding var selectedTab: Tab

    var body: some View {
        NavigationStack {
            ZStack {
                TGBackgroundView()

                if store.months.isEmpty {
                    emptyState
                } else {
                    calendarContent
                }
            }
            .navigationTitle(monthTitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if offlineCache.isOnline == false {
                        Label("Offline", systemImage: "wifi.slash")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingPDFImporter = true
                    } label: {
                        Image(systemName: "doc.badge.plus")
                            .foregroundStyle(TGTheme.indigo)
                    }
                }
            }
            .fileImporter(
                isPresented: $isShowingPDFImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                Task { await importSchedulePDF(result) }
            }
            .alert(item: $alertContext) { context in
                Alert(
                    title: Text(context.title),
                    message: context.message.map { Text($0) },
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    // MARK: - Month Title

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.calendar = .roster
        formatter.timeZone = rosterTimeZone
        return formatter.string(from: displayedMonth)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            TGNoRosterHeroCard(
                action: { isShowingPDFImporter = true },
                isProcessing: isProcessingSchedule
            )
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 84)
    }

    // MARK: - Calendar Content

    private var calendarContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Flight alerts banner
                if alertService.activeAlerts.isEmpty == false {
                    alertsBanner
                }

                // Month navigation
                monthNavigationBar

                // Calendar grid
                calendarGrid

                // Legend
                calendarLegend

                // Selected day detail
                if let selectedDay, selectedDay.events.isEmpty == false {
                    selectedDayDetail(selectedDay)
                }

                // Next flight briefing
                if let briefing = nextFlightBriefing {
                    NextFlightBriefingCard(briefing: briefing)
                }

                // Quick stats for this month
                monthStatsCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Alerts Banner

    private var alertsBanner: some View {
        VStack(spacing: 8) {
            ForEach(alertService.activeAlerts.prefix(3)) { alert in
                FlightAlertBanner(alert: alert) {
                    alertService.dismiss(alert.id)
                }
            }
        }
    }

    // MARK: - Month Navigation

    private var monthNavigationBar: some View {
        HStack(spacing: 16) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    shiftMonth(by: -1)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(TGTheme.indigo)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    displayedMonth = Date()
                    syncActiveMonth()
                }
            } label: {
                Text("Today")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TGTheme.indigo)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    shiftMonth(by: 1)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(TGTheme.indigo)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        let dayEvents = buildDayEvents()
        let calendar = Calendar.roster
        let comps = calendar.dateComponents([.year, .month], from: displayedMonth)
        let firstDayOfMonth = calendar.date(from: comps) ?? displayedMonth
        let weekdayOffset = (calendar.component(.weekday, from: firstDayOfMonth) + 5) % 7 // Monday = 0
        let daysInMonth = calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30
        let today = calendar.component(.day, from: Date())
        let isCurrentMonth = calendar.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)

        return VStack(spacing: 2) {
            // Weekday headers
            HStack(spacing: 0) {
                ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { day in
                    Text(day)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)

            // Day grid
            let totalCells = weekdayOffset + daysInMonth
            let rows = (totalCells + 6) / 7

            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        let cellIndex = row * 7 + col
                        let dayNumber = cellIndex - weekdayOffset + 1

                        if dayNumber >= 1 && dayNumber <= daysInMonth {
                            let events = dayEvents[dayNumber]
                            let isToday = isCurrentMonth && dayNumber == today
                            let isSelected = selectedDay?.day == dayNumber

                            CalendarDayCell(
                                day: dayNumber,
                                flightCount: events?.flightDestinations.count ?? 0,
                                dutyCount: events?.dutyCodes.count ?? 0,
                                swapCount: events?.swapDestinations.count ?? 0,
                                isToday: isToday,
                                isSelected: isSelected
                            )
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    if isSelected {
                                        selectedDay = nil
                                    } else {
                                        selectedDay = events ?? CalendarDayEvents(day: dayNumber, date: Date(), events: [])
                                    }
                                }
                            }
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                    }
                }
            }
        }
        .tgFrostedCard(cornerRadius: 18, verticalPadding: 12)
    }

    // MARK: - Legend

    private var calendarLegend: some View {
        HStack(spacing: 16) {
            legendItem(color: TGTheme.indigo, label: "Flight")
            legendItem(color: .orange, label: "Duty")
            legendItem(color: .green, label: "Swap")
        }
        .font(.caption2)
        .frame(maxWidth: .infinity)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Selected Day Detail

    private func selectedDayDetail(_ dayEvents: CalendarDayEvents) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(dayLabel(dayEvents.day))
                .font(.headline.weight(.semibold))
                .foregroundStyle(TGTheme.indigo)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(Array(dayEvents.events.enumerated()), id: \.offset) { _, event in
                switch event {
                case .flight(let record):
                    flightDetailRow(record)
                case .duty(let record):
                    dutyDetailRow(record)
                case .swap(let listing):
                    swapDetailRow(listing)
                case .dayOff:
                    Text("Day off")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .tgFrostedCard(cornerRadius: 16, verticalPadding: 12)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func flightDetailRow(_ record: FlightLookupRecord) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(TGTheme.indigo)
                .frame(width: 4, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.flightCode)
                    .font(.subheadline.weight(.semibold))
                Text(record.routeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(record.scheduleText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func dutyDetailRow(_ record: FlightLookupRecord) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(.orange)
                .frame(width: 4, height: 36)

            Text(record.flightNumber.uppercased())
                .font(.subheadline.weight(.semibold))

            Spacer()

            Text(record.scheduleText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func swapDetailRow(_ listing: SwapListing) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(.green)
                .frame(width: 4, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(listing.flightCode)
                    .font(.subheadline.weight(.semibold))
                Text("Swap: \(listing.routeText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(listing.status.rawValue.capitalized)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        }
    }

    private func dayLabel(_ day: Int) -> String {
        let calendar = Calendar.roster
        var comps = calendar.dateComponents([.year, .month], from: displayedMonth)
        comps.day = day
        guard let date = calendar.date(from: comps) else { return "Day \(day)" }
        let formatter = DateFormatter()
        formatter.calendar = .roster
        formatter.timeZone = rosterTimeZone
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter.string(from: date)
    }

    // MARK: - Month Stats

    private var monthStatsCard: some View {
        let month = currentMonthRecord
        let flightCount = month.map { countFlights(in: $0) } ?? 0
        let dutyCount = month.map { countDuties(in: $0) } ?? 0

        return Group {
            if let month = month {
                VStack(alignment: .leading, spacing: 8) {
                    // Tappable header
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isMonthStatsExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            TGSectionHeader(title: "This Month", systemImage: "chart.bar")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(isMonthStatsExpanded ? 90 : 0))
                        }
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 20) {
                        statPill(value: "\(flightCount)", label: "Flights")
                        statPill(value: "\(dutyCount)", label: "Duties")
                        statPill(value: "\(month.flightsByDay.count)", label: "Days")
                    }
                    .frame(maxWidth: .infinity)

                    // Expanded flight list
                    if isMonthStatsExpanded {
                        Divider()
                            .overlay(TGTheme.insetStroke.opacity(0.55))

                        monthFlightList(month)
                    }
                }
                .tgFrostedCard(cornerRadius: 16, verticalPadding: 12)
            }
        }
    }

    private func statPill(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(TGTheme.indigo)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func monthFlightList(_ month: RosterMonthRecord) -> some View {
        let sortedDays = month.flightsByDay.keys.sorted()

        return VStack(spacing: 0) {
            ForEach(sortedDays, id: \.self) { day in
                let keys = month.flightsByDay[day] ?? []
                ForEach(Array(keys.enumerated()), id: \.offset) { idx, key in
                    let detail = month.detailsByFlight[key] ?? month.detailsByFlight[key.strippingLeadingZeros()]
                    let isDuty = key.isAlphabeticDutyCode

                    HStack(spacing: 10) {
                        Text("\(day)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, alignment: .trailing)
                            .monospacedDigit()

                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(isDuty ? .orange : TGTheme.indigo)
                            .frame(width: 3, height: 28)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(detail?.flightCode ?? key.uppercased())
                                .font(.caption.weight(.semibold))
                            if let dest = detail?.destination, !isDuty {
                                Text(detail?.routeText ?? dest)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if let schedule = detail?.scheduleText, !schedule.isEmpty {
                            Text(schedule)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.vertical, 4)

                    if !(day == sortedDays.last && idx == keys.count - 1) {
                        Divider()
                            .overlay(TGTheme.insetStroke.opacity(0.3))
                    }
                }
            }
        }
    }

    // MARK: - Data Building

    private var currentMonthRecord: RosterMonthRecord? {
        let comps = Calendar.roster.dateComponents([.year, .month], from: displayedMonth)
        return store.months.first { $0.year == comps.year && $0.month == comps.month }
    }

    private func buildDayEvents() -> [Int: CalendarDayEvents] {
        guard let month = currentMonthRecord else { return [:] }

        var result: [Int: CalendarDayEvents] = [:]
        let calendar = Calendar.roster

        for day in 1...31 {
            var comps = calendar.dateComponents([.year, .month], from: displayedMonth)
            comps.day = day
            guard let date = calendar.date(from: comps) else { continue }
            guard calendar.component(.month, from: date) == calendar.component(.month, from: displayedMonth) else { break }

            let flightKeys = month.flightsByDay[day] ?? []
            var events: [CalendarEventType] = []

            for key in flightKeys {
                if let detail = month.detailsByFlight[key] ?? month.detailsByFlight[key.strippingLeadingZeros()] {
                    if detail.flightNumber.isAlphabeticDutyCode {
                        events.append(.duty(detail))
                    } else {
                        events.append(.flight(detail))
                    }
                } else {
                    let record = FlightLookupRecord(
                        serviceDate: date,
                        flightNumber: key,
                        origin: nil,
                        destination: nil,
                        departureTime: nil,
                        arrivalTime: nil,
                        state: .found,
                        sourceLabel: "Schedule"
                    )
                    if key.isAlphabeticDutyCode {
                        events.append(.duty(record))
                    } else {
                        events.append(.flight(record))
                    }
                }
            }

            if events.isEmpty {
                events.append(.dayOff)
            }

            result[day] = CalendarDayEvents(day: day, date: date, events: events)
        }

        return result
    }

    private func countFlights(in month: RosterMonthRecord) -> Int {
        month.flightsByDay.values.joined().filter { $0.isAlphabeticDutyCode == false }.count
    }

    private func countDuties(in month: RosterMonthRecord) -> Int {
        month.flightsByDay.values.joined().filter { $0.isAlphabeticDutyCode }.count
    }

    private var nextFlightBriefing: NextFlightBriefing? {
        let now = Date()
        var bestRecord: FlightLookupRecord?
        var bestDate: Date?

        for month in store.months {
            for (day, keys) in month.flightsByDay {
                for key in keys {
                    guard key.isAlphabeticDutyCode == false else { continue }
                    guard let detail = month.detailsByFlight[key] ?? month.detailsByFlight[key.strippingLeadingZeros()] else { continue }
                    guard let depTime = detail.departureTime, let depMinutes = depTime.hhmmMinutes else { continue }

                    var comps = DateComponents()
                    comps.calendar = .roster
                    comps.timeZone = rosterTimeZone
                    comps.year = month.year
                    comps.month = month.month
                    comps.day = day
                    comps.hour = depMinutes / 60
                    comps.minute = depMinutes % 60
                    guard let depDate = comps.date, depDate > now else { continue }

                    if bestDate == nil || depDate < bestDate! {
                        bestDate = depDate
                        bestRecord = detail
                    }
                }
            }
        }

        guard let record = bestRecord, let depDate = bestDate else { return nil }

        let number = record.flightNumber.strippingLeadingZeros()
        let displayNumber = number.isEmpty ? "0" : number
        let flightCode = "TG \(displayNumber)"
        let origin = record.origin ?? "BKK"
        let destination = record.destination ?? "???"

        return NextFlightBriefing(
            id: "\(record.flightNumber)-\(depDate.timeIntervalSince1970)",
            flightCode: flightCode,
            originCode: origin,
            destinationCode: destination,
            serviceDate: record.serviceDate,
            departureDate: depDate,
            departureTimeText: record.departureTime,
            arrivalTimeText: record.arrivalTime,
            destinationInfo: DestinationMetadata.info(for: destination)
        )
    }

    // MARK: - Month Navigation

    private func shiftMonth(by value: Int) {
        if let newMonth = Calendar.roster.date(byAdding: .month, value: value, to: displayedMonth) {
            displayedMonth = newMonth
            selectedDay = nil
            syncActiveMonth()
        }
    }

    private func syncActiveMonth() {
        if let month = currentMonthRecord {
            store.setActiveMonth(month.id)
        }
    }

    // MARK: - PDF Import

    private func importSchedulePDF(_ result: Result<[URL], Error>) async {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        isProcessingSchedule = true
        defer { isProcessingSchedule = false }

        do {
            let pdfData = try Data(contentsOf: url, options: .mappedIfSafe)

            // Use current month as fallback
            let now = Date()
            let comps = Calendar.roster.dateComponents([.month, .year], from: now)
            let fallbackMonth = comps.month ?? 1
            let fallbackYear = comps.year ?? 2026

            let service = ScheduleSlipService()
            let parsed = try await service.parse(
                pdfData: pdfData,
                fallbackMonth: fallbackMonth,
                fallbackYear: fallbackYear
            )

            let monthId = String(format: "%04d-%02d", parsed.year, parsed.month)

            // Convert ScheduleFlightDetail → FlightLookupRecord
            var dateComps = DateComponents()
            dateComps.year = parsed.year
            dateComps.month = parsed.month
            dateComps.day = 1
            dateComps.calendar = Calendar.roster
            dateComps.timeZone = rosterTimeZone
            let placeholderDate = dateComps.date ?? Date()

            var recordDetails: [String: FlightLookupRecord] = [:]
            for (key, detail) in parsed.detailsByFlight {
                let normalizedNumber = detail.flightNumber.isEmpty
                    ? key.strippingLeadingZeros()
                    : detail.flightNumber
                recordDetails[key] = FlightLookupRecord(
                    serviceDate: placeholderDate,
                    flightNumber: normalizedNumber,
                    origin: detail.origin,
                    destination: detail.destination,
                    departureTime: detail.departureTime,
                    arrivalTime: detail.arrivalTime,
                    state: .found,
                    sourceLabel: "Schedule"
                )
            }

            let record = RosterMonthRecord(
                id: monthId,
                year: parsed.year,
                month: parsed.month,
                createdAt: Date(),
                flightsByDay: parsed.flightsByDay,
                detailsByFlight: recordDetails
            )
            store.upsertMonth(record)

            // Register flights for crew pairing
            await CrewPairingService.shared.registerFlights(from: record)

            // Start monitoring for flight alerts
            startAlertMonitoring()

            let entryCount = record.flightsByDay.values.joined().count
            alertContext = CalendarAlertContext(
                title: "Roster Imported",
                message: "\(entryCount) entries loaded for \(monthId)."
            )
        } catch {
            alertContext = CalendarAlertContext(
                title: "Import Failed",
                message: error.localizedDescription
            )
        }
    }

    private func startAlertMonitoring() {
        guard let month = currentMonthRecord else { return }
        var flights: [(flightCode: String, origin: String, destination: String, serviceDate: Date, departureDate: Date)] = []

        for (day, keys) in month.flightsByDay {
            for key in keys where key.isAlphabeticDutyCode == false {
                guard let detail = month.detailsByFlight[key] ?? month.detailsByFlight[key.strippingLeadingZeros()] else { continue }
                guard let depTime = detail.departureTime, let depMinutes = depTime.hhmmMinutes else { continue }

                var comps = DateComponents()
                comps.calendar = .roster
                comps.timeZone = rosterTimeZone
                comps.year = month.year
                comps.month = month.month
                comps.day = day
                comps.hour = depMinutes / 60
                comps.minute = depMinutes % 60

                guard let depDate = comps.date else { continue }

                let number = key.strippingLeadingZeros()
                let flightCode = "TG\(number.isEmpty ? "0" : number)"

                flights.append((
                    flightCode: flightCode,
                    origin: detail.origin ?? "BKK",
                    destination: detail.destination ?? "",
                    serviceDate: detail.serviceDate,
                    departureDate: depDate
                ))
            }
        }

        alertService.startMonitoring(flights: flights)
    }
}

// MARK: - Calendar Day Cell

struct CalendarDayCell: View {
    let day: Int
    let flightCount: Int
    let dutyCount: Int
    let swapCount: Int
    let isToday: Bool
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text("\(day)")
                .font(.subheadline.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? .white : isSelected ? TGTheme.indigo : .primary)
                .frame(width: 30, height: 30)
                .background {
                    if isToday {
                        Circle().fill(TGTheme.indigo)
                    } else if isSelected {
                        Circle().fill(TGTheme.indigo.opacity(0.12))
                    }
                }

            HStack(spacing: 3) {
                ForEach(0..<min(flightCount, 2), id: \.self) { _ in
                    Circle().fill(TGTheme.indigo).frame(width: 6, height: 6)
                }
                ForEach(0..<min(dutyCount, 1), id: \.self) { _ in
                    Circle().fill(.orange).frame(width: 6, height: 6)
                }
                ForEach(0..<min(swapCount, 1), id: \.self) { _ in
                    Circle().fill(.green).frame(width: 6, height: 6)
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .contentShape(Rectangle())
    }
}

// MARK: - Flight Alert Banner

struct FlightAlertBanner: View {
    let alert: FlightAlert
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: alert.alertType.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(alertColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(alert.alertType.displayName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(alertColor)
                Text(alert.message)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(alertColor.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(alertColor.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var alertColor: Color {
        switch alert.alertType {
        case .delay: return .orange
        case .gateChange: return .blue
        case .cancellation: return .red
        case .diversion: return .red
        }
    }
}

// MARK: - Alert Context

struct CalendarAlertContext: Identifiable {
    let id = UUID()
    let title: String
    let message: String?
}
