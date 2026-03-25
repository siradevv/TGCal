import SwiftUI
import Charts

struct LogbookView: View {
    @EnvironmentObject private var store: TGCalStore

    @State private var rateTables: [PPBSeason: PPBRateTable] = [:]
    @AppStorage("selectedCrewRank") private var selectedRank: PPBRank = .scc

    var body: some View {
        NavigationStack {
            ZStack {
                TGBackgroundView()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Logbook")
                            .font(.largeTitle.weight(.semibold))

                        if store.months.isEmpty {
                            emptyState
                        } else {
                            lifetimeStatsCard
                            flightHoursChart
                            earningsTrendChart
                            topDestinationsCard
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 28)
                    .padding(.bottom, 24)
                }
            }
            .task {
                loadRateTablesIfNeeded()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No data yet")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Import roster PDFs from the Overview tab to see your logbook analytics.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .tgOverviewCard()
    }

    // MARK: - Lifetime Stats Card

    private var lifetimeStatsCard: some View {
        let stats = lifetimeStats()

        return VStack(alignment: .leading, spacing: 10) {
            TGSectionHeader(title: "Lifetime Totals", systemImage: "chart.bar.fill")

            statRow(title: "Total flights", value: "\(stats.totalFlights)")
            statRow(title: "Block hours", value: formatDuration(stats.totalBlockMinutes))
            statRow(title: "Countries visited", value: "\(stats.countriesVisited)")
            statRow(title: "Months loaded", value: "\(stats.monthsLoaded)")
        }
        .tgOverviewCard(verticalPadding: 12)
    }

    // MARK: - Flight Hours Chart

    private var flightHoursChart: some View {
        let data = monthlyFlightHoursData()

        return VStack(alignment: .leading, spacing: 10) {
            TGSectionHeader(title: "Flight Hours", systemImage: "clock.fill")

            if data.isEmpty {
                Text("No flight hour data available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Chart(data) { entry in
                    BarMark(
                        x: .value("Month", entry.label),
                        y: .value("Hours", entry.hours)
                    )
                    .foregroundStyle(TGTheme.indigo)
                    .cornerRadius(4)
                }
                .chartYAxisLabel("Hours")
                .frame(height: 200)
            }
        }
        .tgOverviewCard(verticalPadding: 14)
    }

    // MARK: - Earnings Trend Chart

    private var earningsTrendChart: some View {
        let data = monthlyEarningsData()

        return VStack(alignment: .leading, spacing: 10) {
            TGSectionHeader(title: "Earnings Trend", systemImage: "banknote.fill")

            if data.isEmpty {
                Text("No earnings data available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Chart(data) { entry in
                    LineMark(
                        x: .value("Month", entry.label),
                        y: .value("THB", entry.earnings)
                    )
                    .foregroundStyle(TGTheme.indigo)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Month", entry.label),
                        y: .value("THB", entry.earnings)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [TGTheme.indigo.opacity(0.3), TGTheme.indigo.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
                .chartYAxisLabel("THB")
                .frame(height: 200)
            }
        }
        .tgOverviewCard(verticalPadding: 14)
    }

    // MARK: - Top Destinations

    private var topDestinationsCard: some View {
        let ranked = rankedDestinations()
        let top = Array(ranked.prefix(10))
        let maxVisits = top.first?.visits ?? 1

        return VStack(alignment: .leading, spacing: 10) {
            TGSectionHeader(title: "Top Destinations", systemImage: "mappin.and.ellipse")

            if top.isEmpty {
                Text("No destination data available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(top.enumerated()), id: \.element.id) { index, destination in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .trailing)

                        Text(destinationDisplayLabel(destination.city))
                            .font(.subheadline.weight(.medium))
                            .frame(width: 130, alignment: .leading)
                            .lineLimit(1)

                        GeometryReader { geometry in
                            let fraction = CGFloat(destination.visits) / CGFloat(max(maxVisits, 1))
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(TGTheme.indigo.opacity(0.7))
                                .frame(width: geometry.size.width * fraction, height: 16)
                                .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 22)

                        Text("\(destination.visits)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .trailing)
                    }
                    .frame(minHeight: 28)
                }
            }
        }
        .tgOverviewCard(verticalPadding: 14)
    }

    // MARK: - Shared UI Helpers

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

    private func formatDuration(_ minutes: Int) -> String {
        let safeMinutes = max(0, minutes)
        let hours = safeMinutes / 60
        let remainingMinutes = safeMinutes % 60
        return String(format: "%dh %02dm", hours, remainingMinutes)
    }

    // MARK: - Data Loading

    private func loadRateTablesIfNeeded() {
        guard rateTables.isEmpty else { return }
        do {
            rateTables = try EarningsCalculator.loadRateTables()
        } catch {
            return
        }
    }

    // MARK: - Calculation: All Records

    private func allRecords() -> [FlightLookupRecord] {
        var built: [FlightLookupRecord] = []

        for month in store.months {
            for day in month.flightsByDay.keys.sorted() {
                guard let date = serviceDate(day: day, month: month.month, year: month.year) else {
                    continue
                }

                for flightKey in month.flightsByDay[day, default: []] {
                    if let resolved = resolveDetail(for: flightKey, detailsByFlight: month.detailsByFlight) {
                        let flightNumber = resolved.detail.flightNumber.isEmpty
                            ? resolved.key
                            : resolved.detail.flightNumber

                        built.append(
                            FlightLookupRecord(
                                serviceDate: date,
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
                                serviceDate: date,
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

    // MARK: - Calculation: Block Minutes

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

    // MARK: - Calculation: Lifetime Stats

    private struct LifetimeStats {
        let totalFlights: Int
        let totalBlockMinutes: Int
        let countriesVisited: Int
        let monthsLoaded: Int
    }

    private func lifetimeStats() -> LifetimeStats {
        let records = allRecords()
        let numericFlights = records.filter { $0.flightNumber.isAlphabeticDutyCode == false }

        let totalBlock = numericFlights.reduce(0) { running, record in
            running + blockMinutes(for: record)
        }

        var countries = Set<String>()
        for record in numericFlights {
            guard let destination = record.destination?.uppercased(),
                  destination.isEmpty == false,
                  destination != "BKK" else {
                continue
            }
            let city = cityName(forIATA: destination)
            if let countryCode = Self.cityToCountryCode[city] {
                countries.insert(countryCode)
            }
        }

        // Also count Thailand itself since BKK is home base
        if numericFlights.isEmpty == false {
            countries.insert("TH")
        }

        return LifetimeStats(
            totalFlights: numericFlights.count,
            totalBlockMinutes: totalBlock,
            countriesVisited: countries.count,
            monthsLoaded: store.months.count
        )
    }

    // MARK: - Calculation: Monthly Flight Hours

    private struct MonthlyHoursEntry: Identifiable {
        let id: String
        let label: String
        let hours: Double
    }

    private func monthlyFlightHoursData() -> [MonthlyHoursEntry] {
        let sorted = store.months.sorted { lhs, rhs in
            if lhs.year != rhs.year { return lhs.year < rhs.year }
            return lhs.month < rhs.month
        }

        return sorted.map { month in
            var totalMinutes = 0

            for day in month.flightsByDay.keys.sorted() {
                guard let date = serviceDate(day: day, month: month.month, year: month.year) else {
                    continue
                }

                for flightKey in month.flightsByDay[day, default: []] {
                    if let resolved = resolveDetail(for: flightKey, detailsByFlight: month.detailsByFlight) {
                        let flightNumber = resolved.detail.flightNumber.isEmpty
                            ? resolved.key
                            : resolved.detail.flightNumber

                        guard flightNumber.isAlphabeticDutyCode == false else { continue }

                        let record = FlightLookupRecord(
                            serviceDate: date,
                            flightNumber: flightNumber,
                            origin: resolved.detail.origin,
                            destination: resolved.detail.destination,
                            departureTime: resolved.detail.departureTime,
                            arrivalTime: resolved.detail.arrivalTime,
                            state: resolved.detail.state,
                            sourceLabel: resolved.detail.sourceLabel
                        )
                        totalMinutes += blockMinutes(for: record)
                    }
                }
            }

            let label = Self.shortMonthLabel(year: month.year, month: month.month)

            return MonthlyHoursEntry(
                id: month.id,
                label: label,
                hours: Double(totalMinutes) / 60.0
            )
        }
    }

    // MARK: - Calculation: Monthly Earnings

    private struct MonthlyEarningsEntry: Identifiable {
        let id: String
        let label: String
        let earnings: Int
    }

    private func monthlyEarningsData() -> [MonthlyEarningsEntry] {
        guard rateTables.isEmpty == false else { return [] }

        let sorted = store.months.sorted { lhs, rhs in
            if lhs.year != rhs.year { return lhs.year < rhs.year }
            return lhs.month < rhs.month
        }

        return sorted.map { month in
            let season = seasonForMonth(month.month)
            let result = EarningsCalculator.calculate(
                for: month,
                season: season,
                rank: selectedRank,
                tables: rateTables
            )

            let label = Self.shortMonthLabel(year: month.year, month: month.month)

            return MonthlyEarningsEntry(
                id: month.id,
                label: label,
                earnings: result.totalTHB
            )
        }
    }

    private func seasonForMonth(_ month: Int) -> PPBSeason {
        // IATA summer schedule: last Sunday of March through last Saturday of October
        // Simplified: April-October = summer, November-March = winter
        switch month {
        case 4...10: return .summer
        default: return .winter
        }
    }

    // MARK: - Calculation: Top Destinations

    private struct DestinationVisit: Identifiable {
        let city: String
        let iataCode: String
        let visits: Int

        var id: String { city }
    }

    private func rankedDestinations() -> [DestinationVisit] {
        var counts: [String: Int] = [:]
        var codeForCity: [String: String] = [:]

        let records = allRecords()
        for record in records where record.flightNumber.isAlphabeticDutyCode == false {
            guard let destination = record.destination?.trimmingCharacters(in: .whitespacesAndNewlines),
                  destination.isEmpty == false else {
                continue
            }

            let normalizedDestination = destination.uppercased()
            guard normalizedDestination != "BKK" else { continue }

            let city = cityName(forIATA: normalizedDestination)
            counts[city, default: 0] += 1
            codeForCity[city] = normalizedDestination
        }

        return counts
            .map { DestinationVisit(city: $0.key, iataCode: codeForCity[$0.key] ?? "", visits: $0.value) }
            .sorted { lhs, rhs in
                if lhs.visits != rhs.visits {
                    return lhs.visits > rhs.visits
                }
                return lhs.city < rhs.city
            }
    }

    // MARK: - Display Helpers

    private func destinationDisplayLabel(_ city: String) -> String {
        let countryCode = Self.cityToCountryCode[city] ?? ""
        guard let flag = flagEmoji(forCountryCode: countryCode) else {
            return city
        }
        return "\(flag) \(city)"
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

    private static func shortMonthLabel(year: Int, month: Int) -> String {
        var components = DateComponents()
        components.calendar = .roster
        components.timeZone = rosterTimeZone
        components.year = year
        components.month = month
        components.day = 1

        let date = components.date ?? Date()
        return shortMonthFormatter.string(from: date)
    }

    // MARK: - Formatters

    private static let shortMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .roster
        formatter.timeZone = rosterTimeZone
        formatter.dateFormat = "MMM"
        return formatter
    }()

    // MARK: - Static Lookup Dictionaries

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
        "Manila": "PH",
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
}
