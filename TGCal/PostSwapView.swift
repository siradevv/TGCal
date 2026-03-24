import SwiftUI

/// Sheet for posting a new flight swap listing.
struct PostSwapView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var supabase = SupabaseService.shared
    @EnvironmentObject private var store: TGCalStore

    @State private var selectedFlight: PostableFlightOption?
    @State private var manualFlightCode = ""
    @State private var manualOrigin = "BKK"
    @State private var manualDestination = ""
    @State private var manualDate = Date()
    @State private var manualDepartureTime = ""
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
                            manualEntrySection
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

            ForEach(rosterFlights) { flight in
                Button {
                    selectedFlight = flight
                } label: {
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

                        Image(systemName: selectedFlight?.id == flight.id ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(selectedFlight?.id == flight.id ? TGTheme.indigo : Color.secondary.opacity(0.3))
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selectedFlight?.id == flight.id ? TGTheme.indigo.opacity(0.08) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .tgOverviewCard(verticalPadding: 12)
    }

    // MARK: - Manual Entry

    private var manualEntrySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TGSectionHeader(title: "Flight Details", systemImage: "airplane")

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

    // MARK: - Validation & Posting

    private var isFormValid: Bool {
        if isManualEntry {
            let hasCode = manualFlightCode.trimmingCharacters(in: .whitespaces).isEmpty == false
            let hasDest = manualDestination.trimmingCharacters(in: .whitespaces).count == 3
            return hasCode && hasDest
        }
        return selectedFlight != nil
    }

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

        if isManualEntry {
            let digits = manualFlightCode.filter(\.isNumber)
            flightCode = "TG \(digits.strippingLeadingZeros())"
            origin = manualOrigin.uppercased().trimmingCharacters(in: .whitespaces)
            destination = manualDestination.uppercased().trimmingCharacters(in: .whitespaces)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            flightDate = dateFormatter.string(from: manualDate)
            departureTime = manualDepartureTime.isEmpty ? nil : manualDepartureTime
        } else if let selected = selectedFlight {
            flightCode = selected.flightCode
            origin = selected.origin.uppercased()
            destination = selected.destination.uppercased()
            flightDate = selected.flightDate
            departureTime = selected.departureTime
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
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note.trimmingCharacters(in: .whitespacesAndNewlines)
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

    var displayDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: flightDate) else { return flightDate }
        let display = DateFormatter()
        display.dateFormat = "EEE, d MMM"
        return display.string(from: date)
    }
}
