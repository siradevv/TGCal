import Foundation
import UIKit

struct EarningsExportService {

    // MARK: - Public API

    static func generatePDF(result: MonthEarningsResult, flightCount: Int) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 595.28, height: 841.89) // A4
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let monthLabel = formatMonth(from: result.monthId)
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.groupingSeparator = ","

        func fmt(_ value: Int) -> String {
            numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
        }

        let data = renderer.pdfData { context in
            context.beginPage()

            let margin: CGFloat = 50
            let contentWidth = pageRect.width - margin * 2
            var y: CGFloat = margin

            // ── Title ──────────────────────────────────────────────
            let titleFont = UIFont.boldSystemFont(ofSize: 22)
            let titleAttr: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.black
            ]
            let title = "TGCal Earnings Report"
            let titleSize = (title as NSString).size(withAttributes: titleAttr)
            (title as NSString).draw(
                at: CGPoint(x: (pageRect.width - titleSize.width) / 2, y: y),
                withAttributes: titleAttr
            )
            y += titleSize.height + 8

            // ── Subtitle (month & season) ──────────────────────────
            let subtitleFont = UIFont.systemFont(ofSize: 14)
            let subtitleAttr: [NSAttributedString.Key: Any] = [
                .font: subtitleFont,
                .foregroundColor: UIColor.darkGray
            ]
            let subtitle = "\(monthLabel)  ·  \(result.season.displayName) Season"
            let subtitleSize = (subtitle as NSString).size(withAttributes: subtitleAttr)
            (subtitle as NSString).draw(
                at: CGPoint(x: (pageRect.width - subtitleSize.width) / 2, y: y),
                withAttributes: subtitleAttr
            )
            y += subtitleSize.height + 24

            // ── Separator ──────────────────────────────────────────
            let separatorPath = UIBezierPath()
            separatorPath.move(to: CGPoint(x: margin, y: y))
            separatorPath.addLine(to: CGPoint(x: pageRect.width - margin, y: y))
            UIColor.gray.setStroke()
            separatorPath.lineWidth = 0.5
            separatorPath.stroke()
            y += 16

            // ── Table header ───────────────────────────────────────
            let headerFont = UIFont.boldSystemFont(ofSize: 12)
            let headerAttr: [NSAttributedString.Key: Any] = [
                .font: headerFont,
                .foregroundColor: UIColor.black
            ]
            let cellFont = UIFont.systemFont(ofSize: 12)
            let cellAttr: [NSAttributedString.Key: Any] = [
                .font: cellFont,
                .foregroundColor: UIColor.black
            ]

            let colX: [CGFloat] = [margin, margin + 160, margin + 260, margin + 370]
            let headers = ["Flight", "Count", "PPB (฿)", "Subtotal (฿)"]

            for (i, header) in headers.enumerated() {
                (header as NSString).draw(at: CGPoint(x: colX[i], y: y), withAttributes: headerAttr)
            }
            y += 20

            // Header underline
            let headerLine = UIBezierPath()
            headerLine.move(to: CGPoint(x: margin, y: y))
            headerLine.addLine(to: CGPoint(x: pageRect.width - margin, y: y))
            UIColor.black.setStroke()
            headerLine.lineWidth = 0.8
            headerLine.stroke()
            y += 8

            // ── Table rows ─────────────────────────────────────────
            let rowHeight: CGFloat = 22
            for item in result.lineItems {
                // Start a new page if needed
                if y + rowHeight > pageRect.height - 100 {
                    context.beginPage()
                    y = margin
                }

                let flightLabel = "TG\(item.flightNumber)"
                let countLabel = "\(item.count)"
                let ppbLabel = item.ppb != nil ? "฿\(fmt(item.ppb!))" : "—"
                let subtotalLabel = "฿\(fmt(item.subtotal))"

                (flightLabel as NSString).draw(at: CGPoint(x: colX[0], y: y), withAttributes: cellAttr)
                (countLabel as NSString).draw(at: CGPoint(x: colX[1], y: y), withAttributes: cellAttr)
                (ppbLabel as NSString).draw(at: CGPoint(x: colX[2], y: y), withAttributes: cellAttr)
                (subtotalLabel as NSString).draw(at: CGPoint(x: colX[3], y: y), withAttributes: cellAttr)

                y += rowHeight
            }

            // ── Total separator ────────────────────────────────────
            y += 4
            let totalLine = UIBezierPath()
            totalLine.move(to: CGPoint(x: margin, y: y))
            totalLine.addLine(to: CGPoint(x: pageRect.width - margin, y: y))
            UIColor.black.setStroke()
            totalLine.lineWidth = 0.8
            totalLine.stroke()
            y += 10

            // ── Total row ──────────────────────────────────────────
            let totalFont = UIFont.boldSystemFont(ofSize: 13)
            let totalAttr: [NSAttributedString.Key: Any] = [
                .font: totalFont,
                .foregroundColor: UIColor.black
            ]
            ("Total" as NSString).draw(at: CGPoint(x: colX[0], y: y), withAttributes: totalAttr)
            ("฿\(fmt(result.totalTHB))" as NSString).draw(at: CGPoint(x: colX[3], y: y), withAttributes: totalAttr)
            y += 30

            // ── Footer info ────────────────────────────────────────
            let footerFont = UIFont.systemFont(ofSize: 10)
            let footerAttr: [NSAttributedString.Key: Any] = [
                .font: footerFont,
                .foregroundColor: UIColor.gray
            ]

            let flightCountLine = "Total flights: \(flightCount)"
            (flightCountLine as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: footerAttr)
            y += 16

            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .long
            let generatedLine = "Generated: \(dateFormatter.string(from: Date()))"
            (generatedLine as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: footerAttr)
        }

        return data
    }

    static func generateCSV(result: MonthEarningsResult, flightCount: Int) -> Data {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.groupingSeparator = ","

        func fmt(_ value: Int) -> String {
            numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
        }

        var lines: [String] = []
        lines.append("Flight,Count,PPB (THB),Subtotal (THB)")

        for item in result.lineItems {
            let flight = "TG\(item.flightNumber)"
            let ppb = item.ppb != nil ? fmt(item.ppb!) : ""
            let subtotal = fmt(item.subtotal)
            lines.append("\(flight),\(item.count),\(ppb),\(subtotal)")
        }

        lines.append("Total,,,\(fmt(result.totalTHB))")

        let csvString = lines.joined(separator: "\n") + "\n"

        // UTF-8 BOM for Excel compatibility
        var data = Data([0xEF, 0xBB, 0xBF])
        if let csvData = csvString.data(using: .utf8) {
            data.append(csvData)
        }
        return data
    }

    // MARK: - Helpers

    private static func formatMonth(from monthId: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: monthId) else { return monthId }

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "MMMM yyyy"
        displayFormatter.locale = Locale(identifier: "en_US")
        return displayFormatter.string(from: date)
    }
}
