import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: TGCalStore

    @StateObject private var calendarService = CalendarService()

    @State private var isProcessingSchedule = false
    @State private var isAddingToCalendar = false
    @State private var isLoadingCalendars = false

    @State private var isShowingPDFImporter = false

    @State private var calendarOptions: [CalendarOption] = []
    @State private var selectedCalendarIdentifier: String?
    @State private var newCalendarName = ""
    @State private var isShowingCreateCalendarSheet = false
    @State private var isShowingExistingCalendarSheet = false

    @State private var selectedSeason: PPBSeason = .summer
    @State private var rateTables: [PPBSeason: PPBRateTable] = [:]
    @State private var loadErrorMessage: String?

    @State private var alertContext: AlertContext?
    @FocusState private var isNewCalendarNameFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()

                List {
                    if sortedMonths.isEmpty {
                        Section {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Flights")
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
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(themeIndigo)
                                .disabled(isProcessingSchedule)

                                if isProcessingSchedule {
                                    HStack(spacing: 10) {
                                        ProgressView()
                                        Text("Reading your schedule...")
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.subheadline)
                                    .transition(.opacity)
                                }
                            }
                            .tgCard()
                            .padding(.vertical, 2)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    } else {
                        Section {
                            HStack(alignment: .center, spacing: 12) {
                                Text(headerTitle)
                                    .font(.largeTitle.weight(.semibold))

                                Spacer(minLength: 8)

                                monthSelectionIndicatorMenu
                            }
                            .padding(.vertical, 2)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }

                        Section {
                            VStack(alignment: .leading, spacing: 12) {
                                if activeMonth != nil {
                                    Picker("Season", selection: $selectedSeason) {
                                        ForEach(PPBSeason.allCases) { season in
                                            Text(season.displayName).tag(season)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                }

                                Button {
                                    isShowingPDFImporter = true
                                } label: {
                                    Text(pdfButtonTitle)
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(themeIndigo)
                                .disabled(isProcessingSchedule)

                                if isProcessingSchedule {
                                    HStack(spacing: 10) {
                                        ProgressView()
                                        Text("Reading your schedule...")
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.subheadline)
                                    .transition(.opacity)
                                }
                            }
                            .tgCard()
                            .padding(.vertical, 2)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }

                    if lookupDayGroups.isEmpty == false {
                        Section {
                            VStack(spacing: 6) {
                                VStack(spacing: 0) {
                                    ForEach(Array(lookupDayGroups.enumerated()), id: \.offset) { index, group in
                                        VStack(alignment: .leading, spacing: 12) {
                                            Text(group.date.rosterDateText)
                                                .font(.headline.weight(.semibold))
                                                .foregroundStyle(themeIndigo)

                                            ForEach(group.records) { record in
                                                let earnings = estimatedEarningsTHB(for: record)
                                                VStack(alignment: .leading, spacing: 6) {
                                                    HStack(alignment: .center, spacing: 10) {
                                                        if record.showsCodeBadge {
                                                            Text(record.flightCode)
                                                                .font(.caption.weight(.semibold))
                                                                .foregroundStyle(themeIndigo)
                                                                .padding(.horizontal, 10)
                                                                .padding(.vertical, 5)
                                                                .background(Capsule().fill(themeIndigo.opacity(0.14)))
                                                        }

                                                        Text(record.listPrimaryText)
                                                            .font(.subheadline)
                                                            .lineLimit(1)
                                                            .frame(maxWidth: .infinity, alignment: .leading)

                                                        Text(record.scheduleText)
                                                            .font(.subheadline.weight(.medium))
                                                            .foregroundStyle(.secondary)
                                                            .monospacedDigit()
                                                            .padding(.horizontal, 10)
                                                            .padding(.vertical, 5)
                                                            .background(Capsule().fill(themeRose.opacity(0.16)))
                                                    }

                                                    if earnings > 0 {
                                                        HStack(spacing: 8) {
                                                            Spacer()

                                                            Text(formatTHB(earnings))
                                                                .font(.caption.weight(.semibold))
                                                                .foregroundStyle(themeIndigo)
                                                                .monospacedDigit()
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.vertical, 12)

                                        if index < lookupDayGroups.count - 1 {
                                            Divider()
                                        }
                                    }
                                }
                                .tgCard(cornerRadius: 16, verticalPadding: 12)
                                .padding(.vertical, 2)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)

                                if let result = earningsResult {
                                    HStack(spacing: 10) {
                                        Text("Estimated Total Earnings")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(themeIndigo)

                                        Spacer()

                                        Text(formatTHB(result.totalTHB))
                                            .font(.headline.weight(.semibold))
                                            .monospacedDigit()
                                    }
                                    .tgCard(cornerRadius: 14, verticalPadding: 10)
                                    .padding(.vertical, 0)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        } header: {
                            sectionHeader("Flights", systemImage: "airplane")
                        }

                        Section {
                            VStack(spacing: 12) {
                                Button {
                                    newCalendarName = ""
                                    isShowingCreateCalendarSheet = true
                                } label: {
                                    Label("Create New Calendar", systemImage: "plus.circle")
                                        .font(.headline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(themeIndigo)
                                .disabled(isAddingToCalendar || isProcessingSchedule)

                                Button {
                                    Task {
                                        await openExistingCalendarSheet()
                                    }
                                } label: {
                                    if isLoadingCalendars {
                                        HStack(spacing: 8) {
                                            ProgressView()
                                            Text("Loading calendars...")
                                                .fontWeight(.semibold)
                                        }
                                        .frame(maxWidth: .infinity)
                                    } else {
                                        Label("Add to Existing Calendar", systemImage: "calendar")
                                            .font(.headline.weight(.semibold))
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .tint(themeIndigo)
                                .disabled(isAddingToCalendar || isProcessingSchedule || isLoadingCalendars)
                            }
                            .tgCard()
                            .padding(.vertical, 2)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        } header: {
                            sectionHeader("Add to Calendar", systemImage: "calendar.badge.plus")
                        }
                    }

                    if activeMonth != nil {
                        if let loadErrorMessage {
                            Section {
                                Text(loadErrorMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .tgCard(cornerRadius: 14, verticalPadding: 12)
                                    .padding(.vertical, 0)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            } footer: {
                                Text("Rates failed to load. Earnings are currently shown as ฿0.")
                                    .textCase(nil)
                            }
                        }

                    }
                }
                .listStyle(.insetGrouped)
                .listSectionSpacing(.compact)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .tint(themeIndigo)
                .opacity(sortedMonths.isEmpty ? 0 : 1)
                .allowsHitTesting(sortedMonths.isEmpty == false)
                .navigationBarTitleDisplayMode(.inline)
                .fileImporter(
                    isPresented: $isShowingPDFImporter,
                    allowedContentTypes: [.pdf],
                    allowsMultipleSelection: false
                ) { result in
                    Task {
                        await importSchedulePDF(result)
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
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            isNewCalendarNameFocused = false
                        }
                    }
                }
                .task {
                    loadRateTablesIfNeeded()
                }
                .sheet(isPresented: $isShowingCreateCalendarSheet) {
                    createCalendarSheet
                }
                .sheet(isPresented: $isShowingExistingCalendarSheet) {
                    existingCalendarSheet
                }

                if sortedMonths.isEmpty {
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
        }
    }

    private var activeMonth: RosterMonthRecord? {
        store.activeMonth
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

    private var activeMonthMenuLabel: String {
        guard let activeMonth else {
            return "Select Month"
        }
        return monthTitle(for: activeMonth)
    }

    private var headerTitle: String {
        guard let activeMonth else {
            return "Flights"
        }
        return monthTitle(for: activeMonth)
    }

    private var headerSummary: String {
        guard let activeMonth else {
            return "No roster loaded. Import a roster PDF to get started."
        }

        let records = records(for: activeMonth)
        let numericFlights = records.filter { $0.flightNumber.isAlphabeticDutyCode == false }
        let totalBlock = numericFlights.reduce(0) { running, record in
            running + blockMinutes(for: record)
        }
        let estimated = earningsResult?.totalTHB ?? 0

        return "\(numericFlights.count) flights • \(formatDuration(totalBlock)) • \(formatTHB(estimated)) estimated"
    }

    private var pdfButtonTitle: String {
        guard let activeMonth else {
            return "Import Roster PDF"
        }
        return "Replace \(monthName(for: activeMonth)) PDF"
    }

    private var activeMonthTitle: String {
        guard let activeMonth else {
            return "No Active Month"
        }
        return monthTitle(for: activeMonth)
    }

    private var activeLookupRecords: [FlightLookupRecord] {
        guard let activeMonth else { return [] }

        return records(for: activeMonth).sorted { lhs, rhs in
            if lhs.serviceDate != rhs.serviceDate {
                return lhs.serviceDate < rhs.serviceDate
            }
            if lhs.departureTime != rhs.departureTime {
                return (lhs.departureTime ?? "9999") < (rhs.departureTime ?? "9999")
            }
            return lhs.flightNumber.paddedFlightNumber() < rhs.flightNumber.paddedFlightNumber()
        }
    }

    private var lookupDayGroups: [LookupDayGroup] {
        let grouped = Dictionary(grouping: activeLookupRecords) { record in
            Calendar.roster.startOfDay(for: record.serviceDate)
        }

        return grouped.keys.sorted().map { date in
            let records = grouped[date, default: []].sorted { lhs, rhs in
                if lhs.departureTime != rhs.departureTime {
                    return (lhs.departureTime ?? "9999") < (rhs.departureTime ?? "9999")
                }
                return lhs.flightNumber.paddedFlightNumber() < rhs.flightNumber.paddedFlightNumber()
            }
            return LookupDayGroup(date: date, records: records)
        }
    }

    private var earningsResult: MonthEarningsResult? {
        guard let month = activeMonth else {
            return nil
        }

        return EarningsCalculator.calculate(
            for: month,
            season: selectedSeason,
            tables: rateTables
        )
    }

    private var perFlightUnitEarningsTHB: [String: Int] {
        guard let result = earningsResult else {
            return [:]
        }

        var values: [String: Int] = [:]
        for item in result.lineItems where item.count > 0 {
            values[item.flightNumber] = item.subtotal / item.count
        }
        return values
    }

    private var themeIndigo: Color {
        TGTheme.indigo
    }

    private var themeRose: Color {
        TGTheme.rose
    }

    private var backgroundGradient: LinearGradient {
        TGTheme.backgroundGradient
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline.weight(.semibold))
            .foregroundStyle(themeIndigo)
            .textCase(nil)
    }

    private var createCalendarSheet: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()

                VStack(spacing: 14) {
                    Form {
                        Section("Calendar name") {
                            TextField("New calendar name", text: $newCalendarName)
                                .textInputAutocapitalization(.words)
                                .focused($isNewCalendarNameFocused)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .tint(themeIndigo)
                    .frame(height: 150)

                    Button {
                        Task {
                            await addToCalendarTapped(mode: .createNew)
                        }
                    } label: {
                        if isAddingToCalendar {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Create Calendar and Add Flights")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(themeIndigo)
                    .disabled(
                        isAddingToCalendar
                        || newCalendarName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle("Create Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        isShowingCreateCalendarSheet = false
                        isNewCalendarNameFocused = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var existingCalendarSheet: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()

                VStack(spacing: 14) {
                    Form {
                        Section("Choose calendar") {
                            if isLoadingCalendars {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text("Loading calendars...")
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Picker("Calendar", selection: $selectedCalendarIdentifier) {
                                    Text("Select Calendar").tag(String?.none)
                                    ForEach(calendarOptions) { option in
                                        Text(option.title).tag(Optional(option.id))
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .tint(themeIndigo)
                    .frame(height: 165)

                    Button {
                        Task {
                            await addToCalendarTapped(mode: .existing)
                        }
                    } label: {
                        if isAddingToCalendar {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Add Flights to Calendar")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(themeIndigo)
                    .disabled(
                        isAddingToCalendar
                        || isLoadingCalendars
                        || selectedCalendarIdentifier == nil
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle("Add to Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        isShowingExistingCalendarSheet = false
                    }
                }
            }
            .task {
                await loadCalendarsIfNeeded()
            }
        }
        .presentationDetents([.medium])
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
            .foregroundStyle(themeIndigo)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var monthSelectionIndicatorMenu: some View {
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
            HStack(spacing: 4) {
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.bold))
            }
            .foregroundStyle(themeIndigo)
            .frame(width: 30, height: 30)
            .background(
                Circle()
                    .fill(TGTheme.controlFill)
            )
            .overlay(
                Circle()
                    .stroke(TGTheme.controlStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func monthTitle(for month: RosterMonthRecord) -> String {
        var components = DateComponents()
        components.calendar = .roster
        components.timeZone = rosterTimeZone
        components.year = month.year
        components.month = month.month
        components.day = 1

        let date = components.date ?? Date()
        let formatter = DateFormatter()
        formatter.calendar = .roster
        formatter.timeZone = rosterTimeZone
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func monthName(for month: RosterMonthRecord) -> String {
        var components = DateComponents()
        components.calendar = .roster
        components.timeZone = rosterTimeZone
        components.year = month.year
        components.month = month.month
        components.day = 1

        let date = components.date ?? Date()
        let formatter = DateFormatter()
        formatter.calendar = .roster
        formatter.timeZone = rosterTimeZone
        formatter.dateFormat = "MMMM"
        return formatter.string(from: date)
    }

    private func loadRateTablesIfNeeded() {
        guard rateTables.isEmpty, loadErrorMessage == nil else { return }

        do {
            rateTables = try EarningsCalculator.loadRateTables()
        } catch {
            loadErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
            alertContext = AlertContext(title: "Could Not Import", message: error.localizedDescription)
            return
        }

        isProcessingSchedule = true
        defer {
            isProcessingSchedule = false
        }

        do {
            let now = Date()
            let fallbackMonth = activeMonth?.month ?? Calendar.roster.component(.month, from: now)
            let fallbackYear = activeMonth?.year ?? Calendar.roster.component(.year, from: now)

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
                if let fileSize, fileSize > ImportLimits.maxPDFBytes {
                    throw PDFImportValidationError.fileTooLarge(maxMB: ImportLimits.maxPDFMegabytes)
                }

                let pdfData = try Data(contentsOf: selectedURL, options: .mappedIfSafe)
                if pdfData.count > ImportLimits.maxPDFBytes {
                    throw PDFImportValidationError.fileTooLarge(maxMB: ImportLimits.maxPDFMegabytes)
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
            }
            if recordCount == 0 {
                alertContext = AlertContext(
                    title: "Could Not Read File",
                    message: "No flights were detected. Please try another PDF file."
                )
            }
        } catch {
            alertContext = AlertContext(title: "Could Not Read File", message: error.localizedDescription)
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
        let placeholderDate = buildServiceDate(day: 1, month: parsed.month, year: parsed.year) ?? Date()

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
            guard let serviceDate = buildServiceDate(day: day, month: month, year: year),
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

    private func buildServiceDate(day: Int, month: Int, year: Int) -> Date? {
        var comps = DateComponents()
        comps.calendar = .roster
        comps.timeZone = rosterTimeZone
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 0
        comps.minute = 0
        return comps.date
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

    private func estimatedEarningsTHB(for record: FlightLookupRecord) -> Int {
        guard let normalized = normalizedNumericFlightNumber(record.flightNumber) else {
            return 0
        }
        return perFlightUnitEarningsTHB[normalized] ?? 0
    }

    private func normalizedNumericFlightNumber(_ raw: String) -> String? {
        let digits = String(raw.filter(\.isNumber))
        guard digits.isEmpty == false else {
            return nil
        }

        let normalized = digits.strippingLeadingZeros()
        if normalized == "0" {
            return nil
        }
        return normalized
    }

    private func missingRows(from missing: [String: Int]) -> [(flight: String, count: Int)] {
        missing
            .map { ($0.key, $0.value) }
            .sorted { lhs, rhs in
                let left = Int(lhs.0) ?? .max
                let right = Int(rhs.0) ?? .max
                if left != right { return left < right }
                return lhs.0 < rhs.0
            }
    }

    @MainActor
    private func addToCalendarTapped(mode: CalendarAddMode) async {
        let drafts = flightDraftsForActiveMonth()
        guard drafts.isEmpty == false else { return }

        isAddingToCalendar = true
        defer {
            isAddingToCalendar = false
        }

        do {
            var destinationCalendarName: String?
            let granted = try await calendarService.requestAccessIfNeeded()
            guard granted else {
                alertContext = AlertContext(
                    title: "Calendar Access Needed",
                    message: "Please allow Calendar access in Settings and try again."
                )
                return
            }

            refreshCalendars()

            if mode == .createNew {
                let trimmed = newCalendarName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.isEmpty == false else {
                    alertContext = AlertContext(
                        title: "New Calendar Name Required",
                        message: "Enter a calendar name."
                    )
                    return
                }

                let calendar = try calendarService.createCalendar(named: trimmed)
                selectedCalendarIdentifier = calendar.calendarIdentifier
                destinationCalendarName = calendar.title
                newCalendarName = ""
                refreshCalendars()
            } else {
                guard let selectedCalendarIdentifier else {
                    alertContext = AlertContext(
                        title: "Choose a Calendar",
                        message: "Select an existing calendar before adding flights."
                    )
                    return
                }
                destinationCalendarName = calendarOptions
                    .first(where: { $0.id == selectedCalendarIdentifier })?
                    .title
            }

            let replaceScope: CalendarMonthScope? = {
                guard mode == .existing, let month = activeMonth else {
                    return nil
                }
                return CalendarMonthScope(year: month.year, month: month.month)
            }()

            let result = try calendarService.addEvents(
                from: drafts,
                to: selectedCalendarIdentifier,
                replaceTGCalEventsInMonth: replaceScope
            )
            let calendarName = destinationCalendarName ?? "selected calendar"
            if mode == .existing, let month = activeMonth {
                let monthLabel = monthTitle(for: month)
                alertContext = AlertContext(
                    title: "Updated \(monthLabel) in \(calendarName): removed \(result.removedCount), added \(result.addedCount) flights"
                )
            } else {
                alertContext = AlertContext(
                    title: "\(result.addedCount) flights added to calendar \(calendarName)"
                )
            }

            if mode == .createNew {
                isShowingCreateCalendarSheet = false
                isNewCalendarNameFocused = false
            } else {
                isShowingExistingCalendarSheet = false
            }
        } catch {
            alertContext = AlertContext(
                title: "Could Not Add Flights",
                message: error.localizedDescription
            )
        }
    }

    private func flightDraftsForActiveMonth() -> [FlightEventDraft] {
        guard let activeMonth else {
            return []
        }

        let monthRecords = records(for: activeMonth)
        let calendar = Calendar.roster
        var built: [FlightEventDraft] = []

        for record in monthRecords where record.state == .found {
            guard let origin = record.origin,
                  let destination = record.destination,
                  let departureText = record.departureTime,
                  let departure = dateFromHHmm(departureText, on: record.serviceDate) else {
                continue
            }

            let arrival: Date
            let hasArrival: Bool

            if let arrivalText = record.arrivalTime,
               let arrivalDate = dateFromHHmm(arrivalText, on: record.serviceDate) {
                arrival = arrivalDate
                hasArrival = true
            } else {
                arrival = calendar.date(byAdding: .hour, value: 2, to: departure) ?? departure.addingTimeInterval(7200)
                hasArrival = false
            }

            var draft = FlightEventDraft(
                serviceDate: calendar.startOfDay(for: record.serviceDate),
                flightNumber: record.flightNumber,
                origin: origin,
                destination: destination,
                departure: departure,
                arrival: arrival,
                hasDepartureTime: true,
                hasArrivalTime: hasArrival,
                confidence: 1,
                rawLines: ["Imported from schedule"]
            )
            draft.normalize()
            built.append(draft)
        }

        return built.sorted { lhs, rhs in
            if lhs.serviceDate != rhs.serviceDate {
                return lhs.serviceDate < rhs.serviceDate
            }
            return lhs.departure < rhs.departure
        }
    }

    private func dateFromHHmm(_ value: String, on serviceDate: Date) -> Date? {
        let digits = value.filter(\.isNumber)
        guard digits.count == 4, let hhmm = Int(digits) else { return nil }
        return Calendar.roster.date(on: serviceDate, hhmm: hhmm)
    }

    private func refreshCalendars() {
        let calendars = calendarService.writableCalendars()
        calendarOptions = calendars.map { CalendarOption(id: $0.calendarIdentifier, title: $0.title) }
        if let selectedCalendarIdentifier,
           calendarOptions.contains(where: { $0.id == selectedCalendarIdentifier }) == false {
            self.selectedCalendarIdentifier = nil
        }
    }

    @MainActor
    private func loadCalendarsIfNeeded() async {
        guard calendarOptions.isEmpty, isLoadingCalendars == false else { return }
        await loadCalendarsTapped()
    }

    @MainActor
    private func openExistingCalendarSheet() async {
        await loadCalendarsIfNeeded()
        isShowingExistingCalendarSheet = true
    }

    @MainActor
    private func loadCalendarsTapped() async {
        isLoadingCalendars = true
        defer {
            isLoadingCalendars = false
        }

        do {
            let granted = try await calendarService.requestAccessIfNeeded()
            guard granted else {
                alertContext = AlertContext(
                    title: "Calendar Access Needed",
                    message: "Please allow Calendar access in Settings and try again."
                )
                return
            }

            refreshCalendars()
        } catch {
            alertContext = AlertContext(
                title: "Calendar Error",
                message: error.localizedDescription
            )
        }
    }
}

private enum CalendarAddMode {
    case createNew
    case existing
}

private struct CalendarOption: Identifiable, Hashable {
    let id: String
    let title: String
}

private struct LookupDayGroup: Identifiable {
    var id: Date { date }
    let date: Date
    let records: [FlightLookupRecord]
}

private struct AlertContext: Identifiable {
    let id = UUID()
    let title: String
    let message: String?

    init(title: String, message: String? = nil) {
        self.title = title
        self.message = message
    }
}

private enum ImportLimits {
    static let maxPDFBytes = 30 * 1024 * 1024
    static let maxPDFMegabytes = maxPDFBytes / (1024 * 1024)
}

private enum PDFImportValidationError: LocalizedError {
    case fileTooLarge(maxMB: Int)

    var errorDescription: String? {
        switch self {
        case let .fileTooLarge(maxMB):
            return "PDF is too large. Please import a file smaller than \(maxMB) MB."
        }
    }
}

private struct TGCardModifier: ViewModifier {
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
                    .shadow(color: TGTheme.cardShadow, radius: 20, x: 0, y: 12)
            )
    }
}

private extension View {
    func tgCard(cornerRadius: CGFloat = 18, verticalPadding: CGFloat = 14) -> some View {
        modifier(TGCardModifier(cornerRadius: cornerRadius, verticalPadding: verticalPadding))
    }
}
