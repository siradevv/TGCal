import SwiftUI

struct EditFlightView: View {
    @Binding var draft: FlightEventDraft

    var body: some View {
        Form {
            Section("Flight") {
                Text("Saved format: \(draft.displayFlightNumber)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextField("Flight Number (digits only)", text: flightNumberBinding)
                    .keyboardType(.numberPad)

                TextField("Origin (IATA)", text: originBinding)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                TextField("Destination (IATA)", text: destinationBinding)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }

            Section("Schedule (Asia/Bangkok)") {
                DatePicker("Date", selection: serviceDateBinding, displayedComponents: .date)
                DatePicker("Depart", selection: departureBinding, displayedComponents: .hourAndMinute)

                if draft.destination == "BKK" {
                    DatePicker("Arrive", selection: arrivalBinding, displayedComponents: .hourAndMinute)
                } else {
                    Text("Arrival time is only kept for returns to BKK.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if draft.needsReview {
                Section("Review") {
                    Text("Needs review")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Edit Flight")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            draft.normalize()
        }
    }

    private var flightNumberBinding: Binding<String> {
        Binding(
            get: { draft.flightNumber },
            set: { newValue in
                draft.flightNumber = String(newValue.filter(\.isNumber).prefix(5))
            }
        )
    }

    private var originBinding: Binding<String> {
        Binding(
            get: { draft.origin },
            set: { newValue in
                draft.origin = String(newValue.uppercased().filter { $0.isLetter }.prefix(3))
            }
        )
    }

    private var destinationBinding: Binding<String> {
        Binding(
            get: { draft.destination },
            set: { newValue in
                let sanitized = String(newValue.uppercased().filter { $0.isLetter }.prefix(3))
                draft.destination = sanitized

                if sanitized != "BKK" {
                    draft.hasArrivalTime = false
                    draft.arrival = draft.departure
                } else if draft.hasArrivalTime == false {
                    draft.hasArrivalTime = true
                    draft.arrival = draft.departure
                }
            }
        )
    }

    private var serviceDateBinding: Binding<Date> {
        Binding(
            get: { draft.serviceDate },
            set: { newDate in
                let calendar = Calendar.roster
                draft.serviceDate = calendar.startOfDay(for: newDate)
                draft.departure = calendar.merging(date: draft.serviceDate, withTimeFrom: draft.departure)

                if draft.hasArrivalTime {
                    draft.arrival = calendar.merging(date: draft.serviceDate, withTimeFrom: draft.arrival)
                    if draft.arrival <= draft.departure {
                        draft.arrival = calendar.date(byAdding: .day, value: 1, to: draft.arrival) ?? draft.arrival.addingTimeInterval(24 * 3600)
                    }
                } else {
                    draft.arrival = draft.departure
                }
            }
        )
    }

    private var departureBinding: Binding<Date> {
        Binding(
            get: { draft.departure },
            set: { newTime in
                let calendar = Calendar.roster
                draft.hasDepartureTime = true
                draft.departure = calendar.merging(date: draft.serviceDate, withTimeFrom: newTime)

                if draft.hasArrivalTime {
                    let rebuiltArrival = calendar.merging(date: draft.serviceDate, withTimeFrom: draft.arrival)
                    if rebuiltArrival <= draft.departure {
                        draft.arrival = calendar.date(byAdding: .day, value: 1, to: rebuiltArrival) ?? rebuiltArrival.addingTimeInterval(24 * 3600)
                    } else {
                        draft.arrival = rebuiltArrival
                    }
                } else {
                    draft.arrival = draft.departure
                }
            }
        )
    }

    private var arrivalBinding: Binding<Date> {
        Binding(
            get: { draft.arrival },
            set: { newTime in
                let calendar = Calendar.roster
                draft.hasArrivalTime = true
                var merged = calendar.merging(date: draft.serviceDate, withTimeFrom: newTime)
                if merged <= draft.departure {
                    merged = calendar.date(byAdding: .day, value: 1, to: merged) ?? merged.addingTimeInterval(24 * 3600)
                }
                draft.arrival = merged
            }
        )
    }
}
