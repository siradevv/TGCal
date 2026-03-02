import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: TGCalStore

    @StateObject private var calendarService = CalendarService()

    @State private var isProcessingSchedule = false
    @State private var isAddingToCalendar = false
    @State private var isLoadingCalendars = false

    @State private var selectedMonth: Int
    @State private var selectedYear: Int

    @State private var isShowingPDFImporter = false
    @State private var lookupRecords: [FlightLookupRecord] = []

    @State private var calendarOptions: [CalendarOption] = []
    @State private var selectedCalendarIdentifier: String?
    @State private var newCalendarName = ""
    @State private var createNewCalendarMode = false

    @State private var alertContext: AlertContext?
    @State private var isShowingHelpActions = false
    @FocusState private var isNewCalendarNameFocused: Bool

    init() {
        let now = Date()
        let calendar = Calendar.roster
        _selectedMonth = State(initialValue: calendar.component(.month, from: now))
        _selectedYear = State(initialValue: calendar.component(.year, from: now))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()

                List {
                    Section {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("TGCal")
                                        .font(.largeTitle.weight(.semibold))

                                    Text("Upload your roster PDF and add flights to your calendar.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "calendar.badge.clock")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(themeIndigo)
                                    .padding(10)
                                    .background(
                                        Circle()
                                            .fill(themeIndigo.opacity(0.14))
                                    )
                            }

                            Button {
                                isShowingPDFImporter = true
                            } label: {
                                Text("Import PDF")
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

                    if lookupRecords.isEmpty == false {
                        Section {
                            ForEach(lookupDayGroups) { group in
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(group.date.rosterDateText)
                                        .font(.headline.weight(.semibold))
                                        .foregroundStyle(themeIndigo)

                                    ForEach(group.records) { record in
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
                                    }
                                }
                                .tgCard(cornerRadius: 16, verticalPadding: 12)
                                .padding(.vertical, 2)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        } header: {
                            sectionHeader("Flights", systemImage: "airplane")
                        }

                        Section {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Create New Calendar")
                                    Spacer()
                                    Toggle("Create New Calendar", isOn: $createNewCalendarMode)
                                        .labelsHidden()
                                }

                                if createNewCalendarMode {
                                    TextField("New calendar name", text: $newCalendarName)
                                        .textInputAutocapitalization(.words)
                                        .focused($isNewCalendarNameFocused)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(themeMint.opacity(0.22))
                                        )
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                }

                                HStack {
                                    Text("Add to Existing Calendar")
                                        .foregroundStyle(createNewCalendarMode ? .secondary : .primary)
                                    Spacer()

                                    if isLoadingCalendars {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Picker("Choose Calendar", selection: $selectedCalendarIdentifier) {
                                            Text("Select Calendar").tag(String?.none)
                                            ForEach(calendarOptions) { option in
                                                Text(option.title).tag(Optional(option.id))
                                            }
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.menu)
                                        .disabled(createNewCalendarMode)
                                        .opacity(createNewCalendarMode ? 0.55 : 1)
                                    }
                                }
                            }
                            .onAppear {
                                Task {
                                    await loadCalendarsIfNeeded()
                                }
                            }
                            .onChange(of: createNewCalendarMode) { _, isEnabled in
                                if isEnabled == false {
                                    isNewCalendarNameFocused = false
                                }
                            }
                            .tgCard()
                            .padding(.vertical, 2)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        } header: {
                            sectionHeader("Add to Calendar", systemImage: "calendar.badge.plus")
                        }

                        Section {
                            Button {
                                Task {
                                    await addToCalendarTapped()
                                }
                            } label: {
                                if isAddingToCalendar {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Text(createNewCalendarMode ? "Create Calendar and Add Flights" : "Add to Calendar")
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .contentTransition(.opacity)
                            .buttonStyle(.borderedProminent)
                            .tint(themeRose)
                            .disabled(
                                isAddingToCalendar
                                || isProcessingSchedule
                                || (createNewCalendarMode && newCalendarName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            )
                            .padding(.top, 2)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }

                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .tint(themeIndigo)
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
                if isShowingHelpActions {
                    Color.black.opacity(0.22)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.16)) {
                                isShowingHelpActions = false
                            }
                        }
                        .transition(.opacity)

                    VStack(spacing: 12) {
                        HStack {
                            Spacer()
                            Button {
                                withAnimation(.easeOut(duration: 0.16)) {
                                    isShowingHelpActions = false
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(8)
                                    .background(Circle().fill(Color.white.opacity(0.6)))
                            }
                            .buttonStyle(.plain)
                        }

                        Text("Support")
                            .font(.title3.weight(.semibold))

                        Button("Privacy Policy") {
                            if let privacyPolicyURL {
                                openURL(privacyPolicyURL)
                            }
                            withAnimation(.easeOut(duration: 0.16)) {
                                isShowingHelpActions = false
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(themeIndigo)
                        .frame(maxWidth: .infinity)

                        Button("Contact Support") {
                            if let supportURL {
                                openURL(supportURL)
                            }
                            withAnimation(.easeOut(duration: 0.16)) {
                                isShowingHelpActions = false
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(themeIndigo)
                        .frame(maxWidth: .infinity)

                        Text(appVersionText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    .padding(18)
                    .frame(maxWidth: 320)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.white.opacity(0.93))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(Color.white.opacity(0.98), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.14), radius: 20, x: 0, y: 12)
                    )
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                    .zIndex(2)
                }

                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        isShowingHelpActions = true
                    }
                } label: {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(themeIndigo)
                        .padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 18)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
    }

    private var supportURL: URL? {
        URL(string: "mailto:tgcal.app@gmail.com?subject=TGCal%20Support")
    }

    private var privacyPolicyURL: URL? {
        URL(string: "https://tgcalapp.github.io/privacy-policy.html")
    }

    private var appVersionText: String {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
        return "App Version \(version)"
    }

    private var themeIndigo: Color {
        Color(red: 0.42, green: 0.50, blue: 0.90)
    }

    private var themeRose: Color {
        Color(red: 0.94, green: 0.60, blue: 0.76)
    }

    private var themeMint: Color {
        Color(red: 0.64, green: 0.89, blue: 0.82)
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.92, green: 0.94, blue: 1.0),
                Color(red: 0.90, green: 0.97, blue: 0.98),
                Color(red: 0.96, green: 0.91, blue: 0.98)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline.weight(.semibold))
            .foregroundStyle(themeIndigo)
            .textCase(nil)
    }

    private var lookupDayGroups: [LookupDayGroup] {
        let grouped = Dictionary(grouping: lookupRecords) { record in
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
            let month = selectedMonth
            let year = selectedYear
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
                    fallbackMonth: month,
                    fallbackYear: year
                )
            }.value

            let recordCount = applyScheduleParseResult(parsed)
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

    @MainActor
    private func applyScheduleParseResult(_ parsed: ScheduleSlipParseResult) -> Int {
        selectedMonth = parsed.month
        selectedYear = parsed.year

        let records = buildLookupRecords(
            month: parsed.month,
            year: parsed.year,
            flightsByDay: parsed.flightsByDay,
            detailsByFlight: parsed.detailsByFlight
        )
        withAnimation(.snappy(duration: 0.30, extraBounce: 0)) {
            lookupRecords = records
        }
        return records.count
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

    @MainActor
    private func addToCalendarTapped() async {
        let drafts = flightDraftsFromLookupRecords()
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

            if createNewCalendarMode {
                let trimmed = newCalendarName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.isEmpty == false else {
                    alertContext = AlertContext(
                        title: "New Calendar Name Required",
                        message: "Enter a calendar name, or turn off Create New Calendar."
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

            let result = try calendarService.addEvents(
                from: drafts,
                to: selectedCalendarIdentifier
            )
            let calendarName = destinationCalendarName ?? "selected calendar"
            alertContext = AlertContext(
                title: "\(result.addedCount) flights added to calendar \(calendarName)"
            )
        } catch {
            alertContext = AlertContext(
                title: "Could Not Add Flights",
                message: error.localizedDescription
            )
        }
    }

    private func flightDraftsFromLookupRecords() -> [FlightEventDraft] {
        let calendar = Calendar.roster
        var built: [FlightEventDraft] = []

        for record in lookupRecords where record.state == .found {
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
                    .fill(Color.white.opacity(0.66))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.95), lineWidth: 1.1)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 20, x: 0, y: 12)
            )
    }
}

private extension View {
    func tgCard(cornerRadius: CGFloat = 18, verticalPadding: CGFloat = 14) -> some View {
        modifier(TGCardModifier(cornerRadius: cornerRadius, verticalPadding: verticalPadding))
    }
}
