import SwiftUI
import UIKit

struct StyledRosterView: View {
    let month: Int
    let year: Int
    let rows: [StyledRosterRow]

    private let leftColumnWidth: CGFloat = 120
    private let rowHeight: CGFloat = 42
    private let headerHeight: CGFloat = 44
    private let headerPurple = Color(red: 74 / 255, green: 0 / 255, blue: 130 / 255)
    private let lavenderRow = Color(red: 232 / 255, green: 230 / 255, blue: 245 / 255)
    private let pinkRow = Color(red: 243 / 255, green: 230 / 255, blue: 238 / 255)

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                dayRow(row: row, isEven: index.isMultiple(of: 2))
            }
        }
        .background(.white)
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color.white, lineWidth: 1)
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
        .overlay(Rectangle().fill(Color.white).frame(width: 1), alignment: .leading)
    }

    private func dayRow(row: StyledRosterRow, isEven: Bool) -> some View {
        let background = isEven ? pinkRow : lavenderRow

        return HStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("\(row.day)")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(red: 106 / 255, green: 88 / 255, blue: 138 / 255))
                    .frame(width: 24, alignment: .leading)

                Text(row.weekdayText)
                    .font(.system(size: 19))
                    .foregroundStyle(Color(red: 106 / 255, green: 88 / 255, blue: 138 / 255))
            }
            .frame(width: leftColumnWidth, alignment: .leading)
            .padding(.leading, 12)
            .background(background)

            Text(row.valueText)
                .font(.system(size: 22))
                .foregroundStyle(Color(red: 54 / 255, green: 42 / 255, blue: 82 / 255))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
                .background(background)
        }
        .frame(height: rowHeight)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white)
                .frame(height: 1)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white)
                .frame(width: 1)
        }
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
