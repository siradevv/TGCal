import SwiftUI
import UniformTypeIdentifiers

struct OverviewView: View {
    @EnvironmentObject private var store: TGCalStore

    @Binding var selectedTab: Tab

    @State private var isShowingDestinationHistory = false
    @State private var rateTables: [PPBSeason: PPBRateTable] = [:]
    @State private var isShowingPDFImporter = false
    @State private var isProcessingSchedule = false
    @State private var alertContext: OverviewAlertContext?
    @State private var isShowingExportSheet = false
    @State private var exportFileURL: URL?

    var body: some View {
        NavigationStack {
            ZStack {
                TGBackgroundView()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if store.months.isEmpty {
                            emptyState
                        } else if let activeMonth = store.activeMonth {
                            loadedState(activeMonth)
                        } else {
                            noActiveMonthState
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 28)
                    .padding(.bottom, 24)
                }
                .opacity(store.months.isEmpty ? 0 : 1)
                .allowsHitTesting(store.months.isEmpty == false)

                if store.months.isEmpty {
                    VStack {
                        Spacer(minLength: 0)
                        TGNoRosterHeroCard(
                            action: { isShowingPDFImporter = true },
                            isProcessing: isProcessingSchedule
                        )
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 84)
                }
            }
            .task {
                loadRateTablesIfNeeded()
            }
            .fileImporter(
                isPresented: $isShowingPDFImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                Task {
                    await importSchedulePDF(result)
                }
            }
            .sheet(isPresented: $isShowingExportSheet) {
                if let exportFileURL {
                    ShareSheetView(activityItems: [exportFileURL])
                }
            }
            .alert(item: $alertContext) { context in
                if let message = context.message, message.isEmpty == false {
                    Alert(
                        title: Text(context.title),
                        message: Text(message),
                        dismissButton: .default(Text("OK"))
                    )
                } else {
                    Alert(
                        title: Text(context.title),
                        dismissButton: .default(Text("OK"))
                    )
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Overview")
                .font(.largeTitle.weight(.semibold))

            Text("No roster loaded")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Import roster PDF to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                isShowingPDFImporter = true
            } label: {
                Text("Import roster PDF")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(TGTheme.indigo)
            .controlSize(.large)
        }
        .tgOverviewCard()
    }

    private var noActiveMonthState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .font(.largeTitle.weight(.semibold))

            Text("Select an active month")
                .font(.headline)
                .foregroundStyle(.secondary)

            monthSelectionMenu(labelText: "Change Month")
        }
        .tgOverviewCard()
    }

    private func loadedState(_ activeMonth: RosterMonthRecord) -> some View {
        let summary = monthSummary(for: activeMonth)
        let destinationHistory = rankedDestinationVisits()
        let nextFlight = nextUpcomingFlight()

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Overview")
                    .font(.largeTitle.weight(.semibold))

                monthSelectionMenu(labelText: monthTitle(for: activeMonth))
            }

            if let nextFlight {
                NextFlightBriefingCard(briefing: nextFlight)
            }

            VStack(alignment: .leading, spacing: 10) {
                TGSectionHeader(title: "Flight Stats", systemImage: "airplane")
                statRow(title: "Total flights", value: "\(summary.numericFlightCount)")
                statRow(title: "Total flying hours", value: formatDuration(summary.totalBlockMinutes))
                statRow(title: "Estimated earnings", value: formatTHB(estimatedEarningsTotal(for: activeMonth)))

                    Divider()

                    Menu {
                        Button {
                            exportEarnings(for: activeMonth, format: .pdf)
                        } label: {
                            Label("Export as PDF", systemImage: "doc.richtext")
                        }
                        Button {
                            exportEarnings(for: activeMonth, format: .csv)
                        } label: {
                            Label("Export as CSV", systemImage: "tablecells")
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                            Text("Export Earnings")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(TGTheme.indigo)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(TGTheme.insetFill)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(TGTheme.insetStroke, lineWidth: 1)
                                )
                        )
                    }
            }
            .tgOverviewCard(verticalPadding: 12)

            VStack(alignment: .leading, spacing: 10) {
                TGSectionHeader(title: "Destinations", systemImage: "mappin.and.ellipse")

                if summary.destinations.isEmpty {
                    Text("No destination data available")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)
                        ],
                        alignment: .leading,
                        spacing: 6
                    ) {
                        ForEach(summary.destinations, id: \.self) { destination in
                            Text(destinationDisplayLabel(destination))
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                if destinationHistory.isEmpty == false {
                    Divider()
                        .padding(.top, 2)

                    DisclosureGroup(isExpanded: $isShowingDestinationHistory) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(destinationHistory) { destination in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(destinationDisplayLabel(destination.city))
                                        .font(.subheadline)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Text("\(destination.visits)")
                                        .font(.footnote.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                .frame(minHeight: 24)
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Past destinations")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(destinationHistory.count) places")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(TGTheme.indigo)
                }
            }
            .tgOverviewCard(verticalPadding: 14)
        }
    }

    private func statRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .frame(minHeight: 28)
    }

    private var sortedMonths: [RosterMonthRecord] {
        store.months.sorted { lhs, rhs in
            if lhs.year != rhs.year {
                return lhs.year > rhs.year
            }
            if lhs.month != rhs.month {
                return lhs.month > rhs.month
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func monthTitle(for month: RosterMonthRecord) -> String {
        var components = DateComponents()
        components.calendar = .roster
        components.timeZone = rosterTimeZone
        components.year = month.year
        components.month = month.month
        components.day = 1

        let date = components.date ?? Date()
        return Self.monthFormatter.string(from: date)
    }

    private func estimatedEarningsTotal(for month: RosterMonthRecord) -> Int {
        guard rateTables.isEmpty == false else {
            return 0
        }

        let season: PPBSeason = (month.month >= 4 && month.month <= 10) ? .summer : .winter
        return EarningsCalculator.calculate(
            for: month,
            season: season,
            tables: rateTables
        ).totalTHB
    }

    private func loadRateTablesIfNeeded() {
        guard rateTables.isEmpty else { return }
        do {
            rateTables = try EarningsCalculator.loadRateTables()
        } catch {
            return
        }
    }

    @MainActor
    private func importSchedulePDF(_ result: Result<[URL], Error>) async {
        let selectedURL: URL

        switch result {
        case let .success(urls):
            guard let first = urls.first else { return }
            selectedURL = first
        case let .failure(error):
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
                return
            }
            alertContext = OverviewAlertContext(title: "Could Not Import", message: error.localizedDescription)
            return
        }

        isProcessingSchedule = true
        defer {
            isProcessingSchedule = false
        }

        do {
            let now = Date()
            let fallbackMonth = store.activeMonth?.month ?? Calendar.roster.component(.month, from: now)
            let fallbackYear = store.activeMonth?.year ?? Calendar.roster.component(.year, from: now)

            let parsed = try await Task.detached(priority: .userInitiated) {
                let didAccess = selectedURL.startAccessingSecurityScopedResource()
                defer {
                    if didAccess {
                        selectedURL.stopAccessingSecurityScopedResource()
                    }
                }

                let sizeKeys: Set<URLResourceKey> = [.fileSizeKey, .totalFileSizeKey]
                let values = try selectedURL.resourceValues(forKeys: sizeKeys)
                let fileSize = values.fileSize ?? values.totalFileSize
                if let fileSize, fileSize > OverviewImportLimits.maxPDFBytes {
                    throw OverviewPDFImportValidationError.fileTooLarge(maxMB: OverviewImportLimits.maxPDFMegabytes)
                }

                let pdfData = try Data(contentsOf: selectedURL, options: .mappedIfSafe)
                if pdfData.count > OverviewImportLimits.maxPDFBytes {
                    throw OverviewPDFImportValidationError.fileTooLarge(maxMB: OverviewImportLimits.maxPDFMegabytes)
                }

                let service = ScheduleSlipService()
                return try await service.parse(
                    pdfData: pdfData,
                    fallbackMonth: fallbackMonth,
                    fallbackYear: fallbackYear
                )
            }.value

            let recordCount = importedRecordCount(parsed)
            if recordCount > 0 {
                persistImportedMonth(parsed)
            } else {
                alertContext = OverviewAlertContext(
                    title: "Could Not Read File",
                    message: "No flights were detected. Please try another PDF file."
                )
            }
        } catch {
            alertContext = OverviewAlertContext(title: "Could Not Read File", message: error.localizedDescription)
        }
    }

    private func importedRecordCount(_ parsed: ScheduleSlipParseResult) -> Int {
        buildLookupRecords(
            month: parsed.month,
            year: parsed.year,
            flightsByDay: parsed.flightsByDay,
            detailsByFlight: parsed.detailsByFlight
        ).count
    }

    private func persistImportedMonth(_ parsed: ScheduleSlipParseResult) {
        let monthId = String(format: "%04d-%02d", parsed.year, parsed.month)
        let placeholderDate = serviceDate(day: 1, month: parsed.month, year: parsed.year) ?? Date()

        var recordDetailsByFlight: [String: FlightLookupRecord] = [:]
        for (key, detail) in parsed.detailsByFlight {
            let normalizedFlightNumber = detail.flightNumber.isEmpty
                ? key.strippingLeadingZeros()
                : detail.flightNumber
            recordDetailsByFlight[key] = FlightLookupRecord(
                serviceDate: placeholderDate,
                flightNumber: normalizedFlightNumber,
                origin: detail.origin,
                destination: detail.destination,
                departureTime: detail.departureTime,
                arrivalTime: detail.arrivalTime,
                state: .found,
                sourceLabel: "Schedule"
            )
        }

        let monthRecord = RosterMonthRecord(
            id: monthId,
            year: parsed.year,
            month: parsed.month,
            createdAt: Date(),
            flightsByDay: parsed.flightsByDay,
            detailsByFlight: recordDetailsByFlight
        )

        store.upsertMonth(monthRecord)
    }

    private func buildLookupRecords(
        month: Int,
        year: Int,
        flightsByDay: [Int: [String]],
        detailsByFlight: [String: ScheduleFlightDetail]
    ) -> [FlightLookupRecord] {
        var built: [FlightLookupRecord] = []

        for day in flightsByDay.keys.sorted() {
            guard let serviceDate = serviceDate(day: day, month: month, year: year),
                  let dayFlights = flightsByDay[day] else {
                continue
            }

            for flightNumber in dayFlights {
                if let resolved = Self.resolveScheduleDetail(
                    for: flightNumber,
                    detailsByFlight: detailsByFlight
                ) {
                    let resolvedFlightNumber = resolved.detail.flightNumber.isEmpty
                        ? resolved.key.strippingLeadingZeros()
                        : resolved.detail.flightNumber
                    built.append(
                        FlightLookupRecord(
                            serviceDate: serviceDate,
                            flightNumber: resolvedFlightNumber,
                            origin: resolved.detail.origin,
                            destination: resolved.detail.destination,
                            departureTime: resolved.detail.departureTime,
                            arrivalTime: resolved.detail.arrivalTime,
                            state: .found,
                            sourceLabel: "Schedule"
                        )
                    )
                }
            }
        }

        return built.sorted { lhs, rhs in
            if lhs.serviceDate != rhs.serviceDate {
                return lhs.serviceDate < rhs.serviceDate
            }
            if lhs.departureTime != rhs.departureTime {
                return (lhs.departureTime ?? "9999") < (rhs.departureTime ?? "9999")
            }
            return lhs.flightNumber.paddedFlightNumber() < rhs.flightNumber.paddedFlightNumber()
        }
    }

    static func resolveScheduleDetail(
        for flightKey: String,
        detailsByFlight: [String: ScheduleFlightDetail]
    ) -> (key: String, detail: ScheduleFlightDetail)? {
        if let exact = detailsByFlight[flightKey] {
            return (flightKey, exact)
        }

        let normalized = flightKey.strippingLeadingZeros()
        if let normalizedDetail = detailsByFlight[normalized] {
            return (normalized, normalizedDetail)
        }

        return nil
    }

    private enum ExportFormat { case pdf, csv }

    private func exportEarnings(for month: RosterMonthRecord, format: ExportFormat) {
        let summary = monthSummary(for: month)
        let earningsResult = EarningsCalculator.calculate(
            for: month,
            season: .summer,
            tables: rateTables
        )

        let data: Data
        let fileName: String
        let monthLabel = monthTitle(for: month).replacingOccurrences(of: " ", with: "_")

        switch format {
        case .pdf:
            data = EarningsExportService.generatePDF(result: earningsResult, flightCount: summary.numericFlightCount)
            fileName = "TGCal_Earnings_\(monthLabel).pdf"
        case .csv:
            data = EarningsExportService.generateCSV(result: earningsResult, flightCount: summary.numericFlightCount)
            fileName = "TGCal_Earnings_\(monthLabel).csv"
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: tempURL, options: .atomic)
            exportFileURL = tempURL
            isShowingExportSheet = true
        } catch {
            alertContext = OverviewAlertContext(title: "Export Failed", message: error.localizedDescription)
        }
    }

    private func monthSummary(for month: RosterMonthRecord) -> MonthSummary {
        let records = records(for: month)
        let numericFlights = records.filter { $0.flightNumber.isAlphabeticDutyCode == false }
        let dutyDays = Set(
            records
                .filter { $0.flightNumber.isAlphabeticDutyCode }
                .map { Calendar.roster.startOfDay(for: $0.serviceDate) }
        )

        let totalBlock = numericFlights.reduce(0) { running, record in
            running + blockMinutes(for: record)
        }

        let averageBlock = numericFlights.isEmpty ? 0 : (totalBlock / numericFlights.count)

        let orderedFlights = numericFlights.sorted { lhs, rhs in
            if lhs.serviceDate != rhs.serviceDate {
                return lhs.serviceDate < rhs.serviceDate
            }
            let lhsDeparture = lhs.departureTime?.hhmmMinutes ?? Int.max
            let rhsDeparture = rhs.departureTime?.hhmmMinutes ?? Int.max
            if lhsDeparture != rhsDeparture {
                return lhsDeparture < rhsDeparture
            }
            return lhs.flightNumber.paddedFlightNumber() < rhs.flightNumber.paddedFlightNumber()
        }

        var destinations: [String] = []
        var seenDestinations = Set<String>()
        for record in orderedFlights {
            guard let destination = record.destination?.trimmingCharacters(in: .whitespacesAndNewlines),
                  destination.isEmpty == false else {
                continue
            }
            let normalizedDestination = destination.uppercased()
            guard normalizedDestination != "BKK" else {
                continue
            }
            if seenDestinations.contains(normalizedDestination) == false {
                seenDestinations.insert(normalizedDestination)
                destinations.append(cityName(forIATA: normalizedDestination))
            }
        }

        return MonthSummary(
            numericFlightCount: numericFlights.count,
            dutyDayCount: dutyDays.count,
            totalBlockMinutes: totalBlock,
            averageBlockMinutes: averageBlock,
            destinations: destinations
        )
    }

    private func records(for month: RosterMonthRecord) -> [FlightLookupRecord] {
        var built: [FlightLookupRecord] = []

        for day in month.flightsByDay.keys.sorted() {
            guard let serviceDate = serviceDate(day: day, month: month.month, year: month.year) else {
                continue
            }

            for flightKey in month.flightsByDay[day, default: []] {
                if let resolved = resolveDetail(for: flightKey, detailsByFlight: month.detailsByFlight) {
                    let flightNumber = resolved.detail.flightNumber.isEmpty
                        ? resolved.key
                        : resolved.detail.flightNumber

                    built.append(
                        FlightLookupRecord(
                            serviceDate: serviceDate,
                            flightNumber: flightNumber,
                            origin: resolved.detail.origin,
                            destination: resolved.detail.destination,
                            departureTime: resolved.detail.departureTime,
                            arrivalTime: resolved.detail.arrivalTime,
                            state: resolved.detail.state,
                            sourceLabel: resolved.detail.sourceLabel
                        )
                    )
                } else {
                    built.append(
                        FlightLookupRecord(
                            serviceDate: serviceDate,
                            flightNumber: flightKey,
                            origin: nil,
                            destination: nil,
                            departureTime: nil,
                            arrivalTime: nil,
                            state: .found,
                            sourceLabel: "Schedule"
                        )
                    )
                }
            }
        }

        return built
    }

    private func allParsedDuties() -> [FlightLookupRecord] {
        store.months.flatMap { records(for: $0) }
    }

    private func nextUpcomingFlight(referenceDate: Date = Date()) -> NextFlightBriefing? {
        let candidates = allParsedDuties()
            .filter { $0.flightNumber.isAlphabeticDutyCode == false }
            .compactMap { record -> (Date, NextFlightBriefing)? in
                guard let departureDate = departureDate(forUpcomingFlight: record),
                      departureDate >= referenceDate else {
                    return nil
                }

                let origin = (record.origin ?? "BKK").uppercased()
                let destination = (record.destination ?? "").uppercased()
                guard destination.isEmpty == false else {
                    return nil
                }

                let digits = String(record.flightNumber.filter(\.isNumber))
                let normalizedNumber = digits.strippingLeadingZeros()
                let flightCode = "TG\(normalizedNumber.isEmpty ? "0" : normalizedNumber)"
                let destinationInfo = DestinationMetadata.info(for: destination)

                let briefing = NextFlightBriefing(
                    id: stableFlightID(for: record),
                    flightCode: flightCode,
                    originCode: origin,
                    destinationCode: destination,
                    serviceDate: record.serviceDate,
                    departureDate: departureDate,
                    departureTimeText: record.departureTime,
                    arrivalTimeText: record.arrivalTime,
                    destinationInfo: destinationInfo
                )

                return (departureDate, briefing)
            }
            .sorted { lhs, rhs in
                if lhs.0 != rhs.0 {
                    return lhs.0 < rhs.0
                }
                return lhs.1.flightCode < rhs.1.flightCode
            }

        return candidates.first?.1
    }

    private func resolveDetail(
        for key: String,
        detailsByFlight: [String: FlightLookupRecord]
    ) -> (key: String, detail: FlightLookupRecord)? {
        if let exact = detailsByFlight[key] {
            return (key, exact)
        }

        let normalized = key.strippingLeadingZeros()
        if let normalizedDetail = detailsByFlight[normalized] {
            return (normalized, normalizedDetail)
        }

        return nil
    }

    private func serviceDate(day: Int, month: Int, year: Int) -> Date? {
        var components = DateComponents()
        components.calendar = .roster
        components.timeZone = rosterTimeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = 0
        components.minute = 0
        return components.date
    }

    private func departureDate(forUpcomingFlight record: FlightLookupRecord) -> Date? {
        let startOfServiceDay = Calendar.roster.startOfDay(for: record.serviceDate)

        guard let departureMinutes = record.departureTime?.hhmmMinutes else {
            return startOfServiceDay
        }

        return Calendar.roster.date(byAdding: .minute, value: departureMinutes, to: startOfServiceDay)
    }

    private func stableFlightID(for record: FlightLookupRecord) -> String {
        let serviceDay = Calendar.roster.startOfDay(for: record.serviceDate)
        let serviceDateText = Self.stableFlightIDDateFormatter.string(from: serviceDay)
        let rawDigits = String(record.flightNumber.filter(\.isNumber))
        let flightNumber = rawDigits.strippingLeadingZeros()
        let origin = (record.origin ?? "UNK").uppercased()
        let destination = (record.destination ?? "UNK").uppercased()
        let departure = record.departureTime ?? "----"
        let arrival = record.arrivalTime ?? "----"
        return [serviceDateText, flightNumber, origin, destination, departure, arrival].joined(separator: "|")
    }

    private func blockMinutes(for record: FlightLookupRecord) -> Int {
        guard let departure = record.departureTime?.hhmmMinutes,
              let arrival = record.arrivalTime?.hhmmMinutes else {
            return 0
        }

        if let timezoneAwareDuration = timezoneAwareFlyingMinutes(
            serviceDate: record.serviceDate,
            departureMinutes: departure,
            arrivalMinutes: arrival,
            origin: record.origin,
            destination: record.destination
        ) {
            return timezoneAwareDuration
        }

        if arrival >= departure {
            return arrival - departure
        }

        return arrival + (24 * 60) - departure
    }

    private func timezoneAwareFlyingMinutes(
        serviceDate: Date,
        departureMinutes: Int,
        arrivalMinutes: Int,
        origin: String?,
        destination: String?
    ) -> Int? {
        guard let originCode = origin?.uppercased(),
              let destinationCode = destination?.uppercased(),
              let originTimeZone = timeZone(forAirportCode: originCode),
              let destinationTimeZone = timeZone(forAirportCode: destinationCode) else {
            return nil
        }

        guard let departureDate = localDate(
            fromServiceDate: serviceDate,
            hhmmMinutes: departureMinutes,
            timeZone: originTimeZone
        ),
        let arrivalBaseDate = localDate(
            fromServiceDate: serviceDate,
            hhmmMinutes: arrivalMinutes,
            timeZone: destinationTimeZone
        ) else {
            return nil
        }

        var destinationCalendar = Calendar(identifier: .gregorian)
        destinationCalendar.timeZone = destinationTimeZone

        var candidates: [Int] = []
        for dayOffset in -1...3 {
            guard let arrivalDate = destinationCalendar.date(byAdding: .day, value: dayOffset, to: arrivalBaseDate) else {
                continue
            }

            let minutes = Int(arrivalDate.timeIntervalSince(departureDate) / 60)
            if (20...16 * 60).contains(minutes) {
                candidates.append(minutes)
            }
        }

        return candidates.min()
    }

    private func localDate(fromServiceDate serviceDate: Date, hhmmMinutes: Int, timeZone: TimeZone) -> Date? {
        let rosterComponents = Calendar.roster.dateComponents([.year, .month, .day], from: serviceDate)

        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = timeZone
        components.year = rosterComponents.year
        components.month = rosterComponents.month
        components.day = rosterComponents.day
        components.hour = hhmmMinutes / 60
        components.minute = hhmmMinutes % 60

        return components.date
    }

    private func timeZone(forAirportCode code: String) -> TimeZone? {
        let identifier = DestinationMetadata.info(for: code).timeZoneIdentifier
        return TimeZone(identifier: identifier)
    }

    private func formatDuration(_ minutes: Int) -> String {
        let safeMinutes = max(0, minutes)
        let hours = safeMinutes / 60
        let remainingMinutes = safeMinutes % 60
        return String(format: "%dh %02dm", hours, remainingMinutes)
    }

    private func formatTHB(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        let number = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "฿\(number)"
    }

    private func monthSelectionMenu(labelText: String) -> some View {
        Menu {
            ForEach(sortedMonths) { month in
                Button {
                    store.setActiveMonth(month.id)
                } label: {
                    HStack {
                        Text(monthTitle(for: month))
                        if store.activeMonthId == month.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(labelText)
                    .font(.headline.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(TGTheme.indigo)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func destinationDisplayLabel(_ destination: String) -> String {
        let countryCode = Self.cityToCountryCode[destination] ?? ""
        guard let flag = flagEmoji(forCountryCode: countryCode) else {
            return "🌍 \(destination)"
        }
        return "\(flag) \(destination)"
    }

    private func rankedDestinationVisits() -> [DestinationVisit] {
        var counts: [String: Int] = [:]

        for record in allParsedDuties() where record.flightNumber.isAlphabeticDutyCode == false {
            guard let destination = record.destination?.trimmingCharacters(in: .whitespacesAndNewlines),
                  destination.isEmpty == false else {
                continue
            }

            let normalizedDestination = destination.uppercased()
            guard normalizedDestination != "BKK" else {
                continue
            }

            let city = cityName(forIATA: normalizedDestination)
            counts[city, default: 0] += 1
        }

        return counts
            .map { DestinationVisit(city: $0.key, visits: $0.value) }
            .sorted { lhs, rhs in
                if lhs.visits != rhs.visits {
                    return lhs.visits > rhs.visits
                }
                return lhs.city < rhs.city
            }
    }

    private func flagEmoji(forCountryCode countryCode: String) -> String? {
        let uppercased = countryCode.uppercased()
        guard uppercased.count == 2 else {
            return nil
        }

        var scalars = String.UnicodeScalarView()
        let regionalIndicatorBase: UInt32 = 127397
        for scalar in uppercased.unicodeScalars {
            guard let flagScalar = UnicodeScalar(regionalIndicatorBase + scalar.value) else {
                return nil
            }
            scalars.append(flagScalar)
        }
        return String(scalars)
    }

    private func cityName(forIATA code: String) -> String {
        let upper = code.uppercased()
        return Self.iataToCity[upper] ?? upper
    }
    private static let stableFlightIDDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .roster
        formatter.timeZone = rosterTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let cityToCountryCode: [String: String] = [
        "Abu Dhabi": "AE",
        "Amsterdam": "NL",
        "Athens": "GR",
        "Auckland": "NZ",
        "Barcelona": "ES",
        "Beijing": "CN",
        "Bengaluru": "IN",
        "Boston": "US",
        "Brisbane": "AU",
        "Brussels": "BE",
        "Busan": "KR",
        "Cairo": "EG",
        "Chengdu": "CN",
        "Chennai": "IN",
        "Chiang Mai": "TH",
        "Chicago": "US",
        "Christchurch": "NZ",
        "Colombo": "LK",
        "Copenhagen": "DK",
        "Dallas": "US",
        "Denpasar": "ID",
        "Delhi": "IN",
        "Dhaka": "BD",
        "Doha": "QA",
        "Dubai": "AE",
        "Frankfurt": "DE",
        "Fukuoka": "JP",
        "Guangzhou": "CN",
        "Hanoi": "VN",
        "Helsinki": "FI",
        "Ho Chi Minh City": "VN",
        "Hong Kong": "HK",
        "Houston": "US",
        "Hyderabad": "IN",
        "Istanbul": "TR",
        "Jakarta": "ID",
        "Jeddah": "SA",
        "Johannesburg": "ZA",
        "Kathmandu": "NP",
        "Kolkata": "IN",
        "Krabi": "TH",
        "Kuala Lumpur": "MY",
        "Kunming": "CN",
        "Kuwait City": "KW",
        "London": "GB",
        "Los Angeles": "US",
        "Macau": "MO",
        "Madrid": "ES",
        "Manchester": "GB",
        "Medan": "ID",
        "Melbourne": "AU",
        "Miami": "US",
        "Milan": "IT",
        "Mumbai": "IN",
        "Munich": "DE",
        "Nagoya": "JP",
        "New York": "US",
        "Newark": "US",
        "Osaka": "JP",
        "Oslo": "NO",
        "Paris": "FR",
        "Penang": "MY",
        "Phnom Penh": "KH",
        "Phuket": "TH",
        "Riyadh": "SA",
        "Rome": "IT",
        "Samui": "TH",
        "San Francisco": "US",
        "Seattle": "US",
        "Seoul": "KR",
        "Shanghai": "CN",
        "Shenzhen": "CN",
        "Singapore": "SG",
        "Stockholm": "SE",
        "Sydney": "AU",
        "Taipei": "TW",
        "Tokyo": "JP",
        "Toronto": "CA",
        "Vancouver": "CA",
        "Vienna": "AT",
        "Vientiane": "LA",
        "Wuhan": "CN",
        "Xi'an": "CN",
        "Xiamen": "CN",
        "Yangon": "MM",
        "Zurich": "CH"
    ]

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .roster
        formatter.timeZone = rosterTimeZone
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private static let iataToCity: [String: String] = [
        "AKL": "Auckland",
        "AMS": "Amsterdam",
        "ARN": "Stockholm",
        "ATH": "Athens",
        "AUH": "Abu Dhabi",
        "BCN": "Barcelona",
        "BLR": "Bengaluru",
        "BNE": "Brisbane",
        "BOM": "Mumbai",
        "BOS": "Boston",
        "BRU": "Brussels",
        "CAI": "Cairo",
        "CAN": "Guangzhou",
        "CCU": "Kolkata",
        "CDG": "Paris",
        "CGK": "Jakarta",
        "CHC": "Christchurch",
        "CMB": "Colombo",
        "CNX": "Chiang Mai",
        "CPH": "Copenhagen",
        "CTU": "Chengdu",
        "DAC": "Dhaka",
        "DEL": "Delhi",
        "DFW": "Dallas",
        "DPS": "Denpasar",
        "DOH": "Doha",
        "DXB": "Dubai",
        "EWR": "Newark",
        "FCO": "Rome",
        "FRA": "Frankfurt",
        "FUK": "Fukuoka",
        "HAN": "Hanoi",
        "HEL": "Helsinki",
        "HKG": "Hong Kong",
        "HKT": "Phuket",
        "HND": "Tokyo",
        "HYD": "Hyderabad",
        "IAH": "Houston",
        "ICN": "Seoul",
        "IST": "Istanbul",
        "JED": "Jeddah",
        "JFK": "New York",
        "JNB": "Johannesburg",
        "KBV": "Krabi",
        "KIX": "Osaka",
        "KMG": "Kunming",
        "KNO": "Medan",
        "KTM": "Kathmandu",
        "KUL": "Kuala Lumpur",
        "KWI": "Kuwait City",
        "LAX": "Los Angeles",
        "LGW": "London",
        "LHR": "London",
        "MAA": "Chennai",
        "MAD": "Madrid",
        "MAN": "Manchester",
        "MEL": "Melbourne",
        "MFM": "Macau",
        "MIA": "Miami",
        "MNL": "Manila",
        "MUC": "Munich",
        "MXP": "Milan",
        "NGO": "Nagoya",
        "NRT": "Tokyo",
        "ORD": "Chicago",
        "OSL": "Oslo",
        "PEK": "Beijing",
        "PEN": "Penang",
        "PKX": "Beijing",
        "PNH": "Phnom Penh",
        "PUS": "Busan",
        "PVG": "Shanghai",
        "RGN": "Yangon",
        "RUH": "Riyadh",
        "SEA": "Seattle",
        "SFO": "San Francisco",
        "SGN": "Ho Chi Minh City",
        "SHA": "Shanghai",
        "SIN": "Singapore",
        "SYD": "Sydney",
        "SZX": "Shenzhen",
        "TPE": "Taipei",
        "USM": "Samui",
        "VIE": "Vienna",
        "VTE": "Vientiane",
        "WUH": "Wuhan",
        "XIY": "Xi'an",
        "XMN": "Xiamen",
        "YVR": "Vancouver",
        "YYZ": "Toronto",
        "ZRH": "Zurich"
    ]

}

private struct MonthSummary {
    let numericFlightCount: Int
    let dutyDayCount: Int
    let totalBlockMinutes: Int
    let averageBlockMinutes: Int
    let destinations: [String]
}

private struct DestinationVisit: Identifiable {
    let city: String
    let visits: Int

    var id: String { city }
}

private struct OverviewAlertContext: Identifiable {
    let id = UUID()
    let title: String
    let message: String?

    init(title: String, message: String? = nil) {
        self.title = title
        self.message = message
    }
}

private enum OverviewImportLimits {
    static let maxPDFBytes = 30 * 1024 * 1024
    static let maxPDFMegabytes = maxPDFBytes / (1024 * 1024)
}

private enum OverviewPDFImportValidationError: LocalizedError {
    case fileTooLarge(maxMB: Int)

    var errorDescription: String? {
        switch self {
        case let .fileTooLarge(maxMB):
            return "PDF is too large. Please import a file smaller than \(maxMB) MB."
        }
    }
}

private struct OverviewCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let verticalPadding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(TGTheme.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(TGTheme.cardStroke, lineWidth: 1.1)
                    )
                    .shadow(color: TGTheme.cardShadow, radius: 14, x: 0, y: 8)
            )
    }
}

extension View {
    func tgOverviewCard(cornerRadius: CGFloat = 18, verticalPadding: CGFloat = 14) -> some View {
        modifier(OverviewCardModifier(cornerRadius: cornerRadius, verticalPadding: verticalPadding))
    }
}

struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
