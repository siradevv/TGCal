import SwiftUI
import UIKit

struct StyledRosterView: View {
    @Environment(\.colorScheme) private var colorScheme

    let month: Int
    let year: Int
    let rows: [StyledRosterRow]

    private let leftColumnWidth: CGFloat = 120
    private let rowHeight: CGFloat = 42
    private let headerHeight: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                dayRow(row: row, isEven: index.isMultiple(of: 2))
            }
        }
        .background(tableBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(gridColor, lineWidth: 1)
        )
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("Date")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: leftColumnWidth, alignment: .leading)
                .padding(.leading, 12)

            Text(monthTitle)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
        }
        .frame(height: headerHeight)
        .background(headerPurple)
        .overlay(Rectangle().fill(gridColor).frame(width: 1), alignment: .leading)
    }

    private func dayRow(row: StyledRosterRow, isEven: Bool) -> some View {
        let background = isEven ? pinkRow : lavenderRow

        return HStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("\(row.day)")
                    .font(.system(size: 20))
                    .foregroundStyle(secondaryTextColor)
                    .frame(width: 24, alignment: .leading)

                Text(row.weekdayText)
                    .font(.system(size: 19))
                    .foregroundStyle(secondaryTextColor)
            }
            .frame(width: leftColumnWidth, alignment: .leading)
            .padding(.leading, 12)
            .background(background)

            Text(row.valueText)
                .font(.system(size: 22))
                .foregroundStyle(primaryTextColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
                .background(background)
        }
        .frame(height: rowHeight)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(gridColor)
                .frame(height: 1)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(gridColor)
                .frame(width: 1)
        }
    }

    private var tableBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.10, green: 0.09, blue: 0.14)
            : .white
    }

    private var headerPurple: Color {
        colorScheme == .dark
            ? Color(red: 0.29, green: 0.20, blue: 0.43)
            : Color(red: 74 / 255, green: 0 / 255, blue: 130 / 255)
    }

    private var lavenderRow: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.15, blue: 0.24)
            : Color(red: 232 / 255, green: 230 / 255, blue: 245 / 255)
    }

    private var pinkRow: Color {
        colorScheme == .dark
            ? Color(red: 0.19, green: 0.15, blue: 0.22)
            : Color(red: 243 / 255, green: 230 / 255, blue: 238 / 255)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark
            ? Color(red: 0.92, green: 0.90, blue: 0.97)
            : Color(red: 54 / 255, green: 42 / 255, blue: 82 / 255)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark
            ? Color(red: 0.80, green: 0.76, blue: 0.90)
            : Color(red: 106 / 255, green: 88 / 255, blue: 138 / 255)
    }

    private var gridColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.16)
            : Color.white
    }

    private var monthTitle: String {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        let date = Calendar.roster.date(from: comps) ?? Date()

        let formatter = DateFormatter()
        formatter.calendar = .roster
        formatter.timeZone = rosterTimeZone
        formatter.dateFormat = "MMMM"
        return "\(formatter.string(from: date))\(year)"
    }
}

@MainActor
func renderStyledRosterImage(month: Int, year: Int, rows: [StyledRosterRow]) -> UIImage? {
    let width: CGFloat = 1200
    let height: CGFloat = 44 + (42 * CGFloat(max(1, rows.count)))

    let content = StyledRosterView(month: month, year: year, rows: rows)
        .frame(width: width, height: height)

    let renderer = ImageRenderer(content: content)
    renderer.scale = 2
    return renderer.uiImage
}

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct StyledRosterPreviewScreen: View {
    let month: Int
    let year: Int
    let rows: [StyledRosterRow]

    @State private var renderedImage: UIImage?
    @State private var showShareSheet = false

    private var renderedHeight: CGFloat {
        44 + (42 * CGFloat(max(1, rows.count)))
    }

    var body: some View {
        List {
            Section("Styled Output") {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    StyledRosterView(month: month, year: year, rows: rows)
                        .frame(width: 1200, height: renderedHeight)
                }
                .frame(height: min(700, renderedHeight + 2))
            }

            Section {
                Button("Render Image") {
                    renderedImage = renderStyledRosterImage(month: month, year: year, rows: rows)
                }

                Button("Share Image") {
                    if renderedImage == nil {
                        renderedImage = renderStyledRosterImage(month: month, year: year, rows: rows)
                    }
                    showShareSheet = renderedImage != nil
                }
                .disabled(rows.isEmpty)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Generated Roster")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if renderedImage == nil {
                renderedImage = renderStyledRosterImage(month: month, year: year, rows: rows)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let renderedImage {
                ActivitySheet(items: [renderedImage])
            }
        }
    }
}
