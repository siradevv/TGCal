import SwiftUI

/// Sheet for posting a new flight swap listing (always round-trip: outbound + return).
struct PostSwapView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var supabase = SupabaseService.shared
    @EnvironmentObject private var store: TGCalStore

    // Roster selection
    @State private var selectedOutbound: PostableFlightOption?
    @State private var autoDetectedReturn: PostableFlightOption?

    // Manual entry — outbound
    @State private var manualFlightCode = ""
    @State private var manualOrigin = "BKK"
    @State private var manualDestination = ""
    @State private var manualDate = Date()
    @State private var manualDepartureTime = ""

    // Manual entry — return
    @State private var manualReturnFlightCode = ""
    @State private var manualReturnOrigin = ""
    @State private var manualReturnDestination = "BKK"
    @State private var manualReturnDate = Date()
    @State private var manualReturnDepartureTime = ""

    @State private var note = ""
    @State private var isManualEntry = false
    @State private var isPosting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                TGBackgroundView()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Quick pick from roster
                        if rosterFlights.isEmpty == false && isManualEntry == false {
                            rosterPickerSection
                        }

                        // Toggle manual entry
                        Button {
                            withAnimation { isManualEntry.toggle() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isManualEntry ? "list.bullet" : "pencil")
                                    .font(.caption.weight(.semibold))
                                Text(isManualEntry ? "Pick from roster" : "Enter manually")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(TGTheme.indigo)
                        }

                        // Manual entry form
                        if isManualEntry {
                            manualOutboundSection
                            manualReturnSection
                        }

                        // Note
                        VStack(alignment: .leading, spacing: 8) {
                            TGSectionHeader(title: "Note (optional)")

                            TextField("e.g. Looking for any Europe flight same date", text: $note, axis: .vertical)
                                .lineLimit(3...6)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(TGTheme.insetFill)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(TGTheme.insetStroke, lineWidth: 1)
                                        )
                                )
                        }
                        .tgOverviewCard(verticalPadding: 12)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        // Post button
                        Button {
                            Task { await postSwap() }
                        } label: {
                            Group {
                                if isPosting {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Post Swap")
                                        .font(.headline.weight(.semibold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(TGTheme.indigo)
                        .disabled(isPosting || !isFormValid)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Post a Swap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Roster Picker

    private var rosterPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TGSectionHeader(title: "Pick from your roster", systemImage: "calendar")

            // Only show outbound flights (departing from BKK)
            ForEach(outboundRosterFlights) { flight in
                Button {
                    selectedOutbound = flight
                    autoDetectedReturn = findReturnFlight(for: flight)
                } label: {
                    rosterFlightRow(flight: flight, returnFlight: findReturnFlight(for: flight), isSelected: selectedOutbound?.id == flight.id)
                }
                .buttonStyle(.plain)
            }

            // Show selected return if auto-detected
            if let outbound = selectedOutbound {
                Divider()
                    .padding(.vertical, 4)

                if let ret = autoDetectedReturn {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Return flight auto-detected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    flightInfoRow(flight: ret, label: "Return")
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text("No return flight found for \(outbound.destination) \u{2192} BKK. Switch to manual entry to add it.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .tgOverviewCard(verticalPadding: 12)
    }

    private func rosterFlightRow(flight: PostableFlightOption, returnFlight: PostableFlightOption?, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // Outbound
                HStack(spacing: 6) {
                    Text(flight.flightCode)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(TGTheme.indigo)
                    Text(flight.routeText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                }

                // Return preview
                if let ret = returnFlight {
                    HStack(spacing: 6) {
                        Text(ret.flightCode)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TGTheme.indigo.opacity(0.7))
                        Text(ret.routeText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(flight.displayDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let time = flight.departureTime {
                    Text(time)
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? TGTheme.indigo : Color.secondary.opacity(0.3))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? TGTheme.indigo.opacity(0.08) : Color.clear)
        )
    }

    private func flightInfoRow(flight: PostableFlightOption, label: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(flight.flightCode)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(TGTheme.indigo)
                Text(flight.routeText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(flight.displayDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let time = flight.departureTime {
                    Text(time)
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(TGTheme.indigo.opacity(0.04))
        )
    }

    // MARK: - Manual Entry

    private var manualOutboundSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TGSectionHeader(title: "Outbound Flight", systemImage: "airplane.departure")

            HStack(spacing: 10) {
                formField(label: "Flight (e.g. 971)", text: $manualFlightCode)
                formField(label: "Origin", text: $manualOrigin)
                    .frame(width: 80)
                formField(label: "Dest", text: $manualDestination)
                    .frame(width: 80)
            }

            HStack(spacing: 10) {
                DatePicker("Date", selection: $manualDate, displayedComponents: .date)
                    .font(.subheadline)
                formField(label: "Dep time", text: $manualDepartureTime)
                    .frame(width: 90)
            }
        }
        .tgOverviewCard(verticalPadding: 12)
        .onChange(of: manualDestination) { _, newValue in
            // Auto-fill return origin from outbound destination
            let trimmed = newValue.uppercased().trimmingCharacters(in: .whitespaces)
            if trimmed.count == 3 {
                manualReturnOrigin = trimmed
            }
        }
        .onChange(of: manualDate) { _, newValue in
            // Default return date to next day
            if let nextDay = Calendar.roster.date(byAdding: .day, value: 1, to: newValue) {
                manualReturnDate = nextDay
            }
        }
    }

    private var manualReturnSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TGSectionHeader(title: "Return Flight", systemImage: "airplane.arrival")

            HStack(spacing: 10) {
                formField(label: "Flight (e.g. 972)", text: $manualReturnFlightCode)
                formField(label: "Origin", text: $manualReturnOrigin)
                    .frame(width: 80)
                formField(label: "Dest", text: $manualReturnDestination)
                    .frame(width: 80)
            }

            HStack(spacing: 10) {
                DatePicker("Date", selection: $manualReturnDate, displayedComponents: .date)
                    .font(.subheadline)
                formField(label: "Dep time", text: $manualReturnDepartureTime)
                    .frame(width: 90)
            }
        }
        .tgOverviewCard(verticalPadding: 12)
    }

    private func formField(label: String, text: Binding<String>) -> some View {
        TextField(label, text: text)
            .font(.subheadline)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(TGTheme.insetFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(TGTheme.insetStroke, lineWidth: 1)
                    )
            )
    }

    // MARK: - Roster Data

    private var rosterFlights: [PostableFlightOption] {
        guard let activeMonth = store.activeMonth else { return [] }
        let now = Date()
        var flights: [PostableFlightOption] = []

        for (day, keys) in activeMonth.flightsByDay {
            for key in keys {
                guard key.isAlphabeticDutyCode == false else { continue }

                let detail: FlightLookupRecord?
                if let exact = activeMonth.detailsByFlight[key] {
                    detail = exact
                } else {
                    detail = activeMonth.detailsByFlight[key.strippingLeadingZeros()]
                }

                guard let detail else { continue }

                var comps = DateComponents()
                comps.calendar = .roster
                comps.timeZone = rosterTimeZone
                comps.year = activeMonth.year
                comps.month = activeMonth.month
                comps.day = day
                guard let serviceDate = comps.date, serviceDate > now else { continue }

                let digits = String(detail.flightNumber.filter(\.isNumber)).strippingLeadingZeros()
                let flightCode = "TG \(digits.isEmpty ? key : digits)"
                let dateString = String(format: "%04d-%02d-%02d", activeMonth.year, activeMonth.month, day)

                flights.append(PostableFlightOption(
                    id: "\(dateString)-\(key)",
                    flightCode: flightCode,
                    origin: detail.origin ?? "BKK",
                    destination: detail.destination ?? "",
                    flightDate: dateString,
                    departureTime: detail.departureTime,
                    serviceDate: serviceDate
                ))
            }
        }

        return flights.sorted { $0.serviceDate < $1.serviceDate }
    }

    /// Only outbound flights (departing from BKK)
    private var outboundRosterFlights: [PostableFlightOption] {
        rosterFlights.filter { $0.origin.uppercased() == "BKK" }
    }

    /// Find the return flight for a given outbound flight.
    /// Looks for a flight from outbound.destination back to BKK within 0-3 days.
    private func findReturnFlight(for outbound: PostableFlightOption) -> PostableFlightOption? {
        let dest = outbound.destination.uppercased()
        guard !dest.isEmpty else { return nil }

        // Find flights from destination back to BKK within 0-3 days of outbound
        let candidates = rosterFlights.filter { flight in
            flight.origin.uppercased() == dest &&
            flight.destination.uppercased() == "BKK" &&
            flight.serviceDate >= outbound.serviceDate &&
            flight.serviceDate <= outbound.serviceDate.addingTimeInterval(3 * 24 * 3600)
        }

        // Return the earliest matching return flight
        return candidates.min(by: { $0.serviceDate < $1.serviceDate })
    }

    // MARK: - Validation & Posting

    private var isFormValid: Bool {
        if isManualEntry {
            let hasCode = manualFlightCode.trimmingCharacters(in: .whitespaces).isEmpty == false
            let hasDest = manualDestination.trimmingCharacters(in: .whitespaces).count == 3
            let hasReturnCode = manualReturnFlightCode.trimmingCharacters(in: .whitespaces).isEmpty == false
            let hasReturnOrigin = manualReturnOrigin.trimmingCharacters(in: .whitespaces).count == 3
            return hasCode && hasDest && hasReturnCode && hasReturnOrigin
        }
        return selectedOutbound != nil
    }

    private static let postDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = rosterTimeZone
        return f
    }()

    private func postSwap() async {
        guard let user = supabase.currentUser else { return }
        isPosting = true
        errorMessage = nil
        defer { isPosting = false }

        let flightCode: String
        let origin: String
        let destination: String
        let flightDate: String
        let departureTime: String?
        let returnFlightCode: String?
        let returnOrigin: String?
        let returnDestination: String?
        let returnFlightDate: String?
        let returnDepartureTime: String?

        if isManualEntry {
            let digits = manualFlightCode.filter(\.isNumber)
            flightCode = "TG \(digits.strippingLeadingZeros())"
            origin = manualOrigin.uppercased().trimmingCharacters(in: .whitespaces)
            destination = manualDestination.uppercased().trimmingCharacters(in: .whitespaces)
            flightDate = Self.postDateFormatter.string(from: manualDate)
            departureTime = manualDepartureTime.isEmpty ? nil : manualDepartureTime

            let retDigits = manualReturnFlightCode.filter(\.isNumber)
            returnFlightCode = "TG \(retDigits.strippingLeadingZeros())"
            returnOrigin = manualReturnOrigin.uppercased().trimmingCharacters(in: .whitespaces)
            returnDestination = manualReturnDestination.uppercased().trimmingCharacters(in: .whitespaces)
            returnFlightDate = Self.postDateFormatter.string(from: manualReturnDate)
            returnDepartureTime = manualReturnDepartureTime.isEmpty ? nil : manualReturnDepartureTime
        } else if let outbound = selectedOutbound {
            flightCode = outbound.flightCode
            origin = outbound.origin.uppercased()
            destination = outbound.destination.uppercased()
            flightDate = outbound.flightDate
            departureTime = outbound.departureTime

            if let ret = autoDetectedReturn {
                returnFlightCode = ret.flightCode
                returnOrigin = ret.origin.uppercased()
                returnDestination = ret.destination.uppercased()
                returnFlightDate = ret.flightDate
                returnDepartureTime = ret.departureTime
            } else {
                returnFlightCode = nil
                returnOrigin = nil
                returnDestination = nil
                returnFlightDate = nil
                returnDepartureTime = nil
            }
        } else {
            return
        }

        let newListing = NewSwapListing(
            postedBy: user.id,
            postedByName: user.displayName,
            flightCode: flightCode,
            origin: origin,
            destination: destination,
            flightDate: flightDate,
            departureTime: departureTime,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note.trimmingCharacters(in: .whitespacesAndNewlines),
            returnFlightCode: returnFlightCode,
            returnOrigin: returnOrigin,
            returnDestination: returnDestination,
            returnFlightDate: returnFlightDate,
            returnDepartureTime: returnDepartureTime
        )

        do {
            _ = try await SwapService.shared.createListing(newListing)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Postable Flight Option

struct PostableFlightOption: Identifiable {
    let id: String
    let flightCode: String
    let origin: String
    let destination: String
    let flightDate: String
    let departureTime: String?
    let serviceDate: Date

    var routeText: String {
        "\(origin) \u{2192} \(destination)"
    }

    private static let parseFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, d MMM"
        f.locale = Locale(identifier: "en_US")
        return f
    }()

    var displayDate: String {
        guard let date = Self.parseFormatter.date(from: flightDate) else { return flightDate }
        return Self.displayFormatter.string(from: date)
    }
}
