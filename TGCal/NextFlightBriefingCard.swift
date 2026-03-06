import SwiftUI

struct NextFlightBriefing: Identifiable, Equatable {
    let id: String
    let flightCode: String
    let originCode: String
    let destinationCode: String
    let serviceDate: Date
    let departureDate: Date
    let departureTimeText: String?
    let arrivalTimeText: String?
    let destinationInfo: DestinationInfo
}

struct NextFlightBriefingCard: View {
    let briefing: NextFlightBriefing

    @State private var hasBriefingNote = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                NextFlightBriefingDetailView(briefing: briefing)
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("✈ Next Flight")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(TGTheme.indigo)

                        Text("\(briefing.flightCode) • \(briefing.originCode) → \(briefing.destinationCode)")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Text(departureDateTimeText())
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Spacer(minLength: 6)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()

            NavigationLink {
                BriefingNoteEditorView(briefing: briefing)
            } label: {
                HStack(spacing: 8) {
                    infoRow(
                        icon: "📝",
                        text: hasBriefingNote ? "Briefing note added" : "Add briefing note",
                        isSecondary: hasBriefingNote == false
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tgOverviewCard(cornerRadius: 22, verticalPadding: 16)
        .task(id: briefing.id) {
            refreshNoteState()
        }
        .onAppear {
            refreshNoteState()
        }
    }

    private func infoRow(icon: String, text: String, isSecondary: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(icon)
                .font(.subheadline)

            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSecondary ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)
        }
    }

    private func departureDateTimeText() -> String {
        "Departs \(departureDateFormatter.string(from: briefing.departureDate))"
    }

    private func refreshNoteState() {
        hasBriefingNote = BriefingNotesStore.hasNote(for: briefing.id)
    }

    private var departureDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = .roster
        formatter.timeZone = rosterTimeZone
        formatter.dateFormat = "EEE, d MMM • HH:mm"
        return formatter
    }

}

struct BriefingNoteEditorView: View {
    let briefing: NextFlightBriefing

    @Environment(\.dismiss) private var dismiss
    @State private var noteText: String

    init(briefing: NextFlightBriefing) {
        self.briefing = briefing
        _noteText = State(initialValue: BriefingNotesStore.note(for: briefing.id) ?? "")
    }

    var body: some View {
        ZStack {
            TGBackgroundView()

            VStack(alignment: .leading, spacing: 12) {
                Text("\(briefing.flightCode) • \(briefing.originCode) → \(briefing.destinationCode)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TGTheme.indigo)

                TextEditor(text: $noteText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(TGTheme.insetFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(TGTheme.insetStroke, lineWidth: 1)
                            )
                    )
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .navigationTitle("Briefing Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    saveAndDismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .onDisappear {
            save()
        }
    }

    private func saveAndDismiss() {
        save()
        dismiss()
    }

    private func save() {
        BriefingNotesStore.save(note: noteText, for: briefing.id)
    }
}

struct NextFlightBriefingDetailView: View {
    let briefing: NextFlightBriefing

    @State private var weather: DestinationWeather?
    @State private var weatherLoadFailed = false
    @State private var conversion: CurrencyQuickConversion?
    @State private var conversionLoadFailed = false
    @State private var liveDetails: LiveFlightDetails?
    @State private var isPowerExpanded = false

    private let defaultAmountTHB: Double = 1

    var body: some View {
        ZStack {
            TGBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(briefing.destinationInfo.cityName)
                        .font(.largeTitle.weight(.semibold))

                    VStack(alignment: .leading, spacing: 10) {
                        TGSectionHeader(title: "✈ Flight details")
                        briefingRow(title: "Route", value: "\(briefing.originCode) → \(briefing.destinationCode)")
                        Divider()
                        eventDetailRow(
                            title: "Departure",
                            value: departureDetailText,
                            airportCode: briefing.originCode,
                            aircraftType: departureAircraftText,
                            gate: departureGateText
                        )
                        Divider()
                        eventDetailRow(
                            title: "Arrival",
                            value: arrivalDetailText,
                            airportCode: briefing.destinationCode,
                            aircraftType: arrivalAircraftText,
                            gate: arrivalGateText
                        )
                    }
                    .tgOverviewCard(verticalPadding: 14)

                    VStack(alignment: .leading, spacing: 10) {
                        TGSectionHeader(title: "🌦 Arrival Conditions")
                        briefingRow(title: "Arrival weather", value: weatherText)
                        Divider()
                        briefingRow(title: "Precipitation", value: precipitationText)
                        Divider()
                        briefingRow(title: "Wind", value: windText)
                        Divider()
                        briefingRow(title: "Humidity", value: humidityText)
                    }
                    .tgOverviewCard(verticalPadding: 14)

                    VStack(alignment: .leading, spacing: 10) {
                        TGSectionHeader(title: "💱 Travel Essentials")
                        TimelineView(.periodic(from: .now, by: 60)) { timeline in
                            briefingRow(title: "Time Difference", value: timeDifferenceText(reference: timeline.date))
                        }
                        Divider()
                        briefingRow(title: "Currency", value: currencyText)
                        Divider()
                        powerExpandableRow()
                    }
                    .tgOverviewCard(verticalPadding: 14)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Next Flight")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: briefing.id) {
            await loadDetailData()
        }
    }

    private func briefingRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
        .frame(minHeight: 30)
    }

    private func eventDetailRow(
        title: String,
        value: String,
        airportCode: String,
        aircraftType: String,
        gate: String
    ) -> some View {
        let gateAvailable = gate != "Not available"
        let aircraftAvailable = aircraftType != "Not available"

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
            }
            .frame(minHeight: 30)

            VStack(alignment: .leading, spacing: 8) {
                Text("\(AirportDirectory.name(for: airportCode)) (\(airportCode))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if gateAvailable {
                    Text(normalizedGateText(gate))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                if aircraftAvailable {
                    Text(aircraftType)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                if gateAvailable == false && aircraftAvailable == false {
                    Text("Terminal, gate, and aircraft update closer to departure.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if gateAvailable == false {
                    Text("Terminal and gate update closer to departure.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if aircraftAvailable == false {
                    Text("Aircraft updates closer to departure.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(TGTheme.insetFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(TGTheme.insetStroke, lineWidth: 1)
                    )
            )
        }
    }

    private func powerExpandableRow() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPowerExpanded.toggle()
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Power")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 12)

                    Text("\(briefing.destinationInfo.plugType.displayLabel) • \(briefing.destinationInfo.voltage)V")
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()

                    Image(systemName: isPowerExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isPowerExpanded {
                HStack(spacing: 10) {
                    plugPreviewCard(
                        title: "Male plug",
                        assetName: briefing.destinationInfo.plugType.assetName
                    )
                    plugPreviewCard(
                        title: "Female socket",
                        assetName: "PlugSocketType\(briefing.destinationInfo.plugType.rawValue)"
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func plugPreviewCard(title: String, assetName: String) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Image(assetName)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(height: 92)
                .foregroundStyle(TGTheme.indigo)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(TGTheme.insetFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(TGTheme.insetStroke, lineWidth: 1)
                )
        )
    }

    private func normalizedGateText(_ text: String) -> String {
        text.replacingOccurrences(of: " Gate ", with: " • Gate ")
    }

    private var weatherText: String {
        if let weather {
            return "\(weather.temperatureCelsius)°C • \(weather.condition.rawValue)"
        }
        if weatherLoadFailed {
            return "Arrival weather unavailable"
        }
        return "Loading arrival weather..."
    }

    private var precipitationText: String {
        if let value = weather?.precipitationChancePercent {
            return "\(value)%"
        }
        if weatherLoadFailed {
            return "Unavailable"
        }
        return "Loading..."
    }

    private var windText: String {
        if let value = weather?.windSpeedKph {
            return "\(value) km/h"
        }
        if weatherLoadFailed {
            return "Unavailable"
        }
        return "Loading..."
    }

    private var humidityText: String {
        if let value = weather?.humidityPercent {
            return "\(value)%"
        }
        if weatherLoadFailed {
            return "Unavailable"
        }
        return "Loading..."
    }

    private var currencyText: String {
        if let conversion {
            return "1 THB = \(formatExchangeRate(conversion.destinationAmount)) \(conversion.destinationCurrencyCode)"
        }
        if conversionLoadFailed {
            return "Rate unavailable"
        }
        return "Loading rate..."
    }

    private func timeDifferenceText(reference: Date) -> String {
        let destinationTimeZone = TimeZone(identifier: briefing.destinationInfo.timeZoneIdentifier) ?? rosterTimeZone
        let bangkokTimeZone = TimeZone(identifier: "Asia/Bangkok") ?? rosterTimeZone

        let destinationOffsetHours = Double(destinationTimeZone.secondsFromGMT(for: reference)) / 3600
        let bangkokOffsetHours = Double(bangkokTimeZone.secondsFromGMT(for: reference)) / 3600
        let delta = destinationOffsetHours - bangkokOffsetHours

        let localTime = timeFormatter(for: destinationTimeZone).string(from: reference)
        return "\(localTime) • \(formatHourDelta(delta)) from BKK"
    }

    private var departureDetailText: String {
        guard let departureTimeText = briefing.departureTimeText,
              let departureMinutes = departureTimeText.hhmmMinutes else {
            return "Not available"
        }

        let originTimeZone = timeZone(forAirportCode: briefing.originCode) ?? rosterTimeZone
        guard let departureDate = localDate(
            serviceDate: briefing.serviceDate,
            hhmmMinutes: departureMinutes,
            timeZone: originTimeZone
        ) else {
            return departureTimeText
        }

        return detailDateFormatter(for: originTimeZone).string(from: departureDate)
    }

    private var arrivalDetailText: String {
        guard let resolvedArrivalDate else {
            return "Not available"
        }

        let destinationTimeZone = TimeZone(identifier: briefing.destinationInfo.timeZoneIdentifier) ?? rosterTimeZone
        return detailDateFormatter(for: destinationTimeZone).string(from: resolvedArrivalDate)
    }

    private var resolvedArrivalDate: Date? {
        guard let arrivalTimeText = briefing.arrivalTimeText,
              let arrivalMinutes = arrivalTimeText.hhmmMinutes else {
            return nil
        }

        let destinationTimeZone = TimeZone(identifier: briefing.destinationInfo.timeZoneIdentifier) ?? rosterTimeZone
        guard let baseArrivalDate = localDate(
            serviceDate: briefing.serviceDate,
            hhmmMinutes: arrivalMinutes,
            timeZone: destinationTimeZone
        ) else {
            return nil
        }

        guard let departureMinutes = briefing.departureTimeText?.hhmmMinutes,
              let originTimeZone = timeZone(forAirportCode: briefing.originCode),
              let departureDate = localDate(
                serviceDate: briefing.serviceDate,
                hhmmMinutes: departureMinutes,
                timeZone: originTimeZone
              ) else {
            return baseArrivalDate
        }

        var destinationCalendar = Calendar(identifier: .gregorian)
        destinationCalendar.timeZone = destinationTimeZone

        var bestCandidate: Date?
        var smallestPositiveMinutes: Int?
        for dayOffset in -1...3 {
            guard let candidate = destinationCalendar.date(byAdding: .day, value: dayOffset, to: baseArrivalDate) else {
                continue
            }

            let minutes = Int(candidate.timeIntervalSince(departureDate) / 60)
            guard minutes >= 0 else {
                continue
            }

            if smallestPositiveMinutes == nil || minutes < smallestPositiveMinutes! {
                smallestPositiveMinutes = minutes
                bestCandidate = candidate
            }
        }

        return bestCandidate ?? baseArrivalDate
    }

    private var departureGateText: String {
        liveDetails?.departureGate ?? "Not available"
    }

    private var arrivalGateText: String {
        liveDetails?.arrivalGate ?? "Not available"
    }

    private var departureAircraftText: String {
        if let type = liveDetails?.departureAircraftType ?? liveDetails?.aircraftType {
            return type
        }
        return "Not available"
    }

    private var arrivalAircraftText: String {
        if let type = liveDetails?.arrivalAircraftType ?? liveDetails?.aircraftType {
            return type
        }
        return "Not available"
    }

    private func timeZone(forAirportCode code: String) -> TimeZone? {
        let identifier = DestinationMetadata.info(for: code).timeZoneIdentifier
        return TimeZone(identifier: identifier)
    }

    private func localDate(serviceDate: Date, hhmmMinutes: Int, timeZone: TimeZone) -> Date? {
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

    private func detailDateFormatter(for timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE, d MMM • HH:mm"
        return formatter
    }

    private func formatHourDelta(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "-"
        let absolute = abs(value)
        if absolute.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(sign)\(Int(absolute))h"
        }
        return "\(sign)\(String(format: "%.1f", absolute))h"
    }

    private func formatExchangeRate(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","

        switch value {
        case 100...:
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
        case 1...:
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 3
        case 0.1...:
            formatter.minimumFractionDigits = 3
            formatter.maximumFractionDigits = 4
        default:
            formatter.minimumFractionDigits = 4
            formatter.maximumFractionDigits = 5
        }

        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.4f", value)
    }

    private func timeFormatter(for timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    private func loadDetailData() async {
        do {
            guard let arrivalDate = resolvedArrivalDate else {
                throw URLError(.cannotParseResponse)
            }

            weather = try await WeatherService.shared.arrivalWeather(
                latitude: briefing.destinationInfo.latitude,
                longitude: briefing.destinationInfo.longitude,
                arrivalDate: arrivalDate,
                timeZoneIdentifier: briefing.destinationInfo.timeZoneIdentifier
            )
            weatherLoadFailed = false
        } catch {
            weather = nil
            weatherLoadFailed = true
        }

        do {
            conversion = try await CurrencyExchangeService.shared.convertTHBToDestination(
                amountTHB: defaultAmountTHB,
                destinationCurrencyCode: briefing.destinationInfo.currencyCode
            )
            conversionLoadFailed = false
        } catch {
            conversion = nil
            conversionLoadFailed = true
        }

        do {
            liveDetails = try await AviationstackService.shared.nextFlightDetails(
                flightCode: briefing.flightCode,
                originCode: briefing.originCode,
                destinationCode: briefing.destinationCode,
                serviceDate: briefing.serviceDate,
                expectedDepartureDate: briefing.departureDate
            )
        } catch {
            liveDetails = nil
        }
    }
}
