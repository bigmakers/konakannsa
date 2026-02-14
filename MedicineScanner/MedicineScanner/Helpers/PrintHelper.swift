import UIKit

// MARK: - UIImage Monochrome Extension

extension UIImage {
    /// Returns a grayscale version with increased contrast, suitable for
    /// reading scale/weight displays clearly.
    func monochromed(contrast: CGFloat = 1.3) -> UIImage {
        guard let ciImage = CIImage(image: self),
              let filter = CIFilter(name: "CIColorControls") else { return self }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(0.0, forKey: kCIInputSaturationKey)
        filter.setValue(contrast, forKey: kCIInputContrastKey)
        guard let output = filter.outputImage else { return self }
        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return self }
        return UIImage(cgImage: cgImage, scale: scale, orientation: imageOrientation)
    }
}

/// Generates a printable composite image combining the medicine name (text)
/// and the captured photo into a single page layout suitable for AirPrint.
enum PrintHelper {

    // MARK: - Layout

    /// Predefined page sizes.
    enum PageLayout {
        /// A4 portrait (210 × 297 mm at 72 ppi ≈ 595 × 842 pt)
        case a4
        /// Compact label (100 × 150 mm at 72 ppi ≈ 283 × 425 pt)
        case label
        /// 58mm receipt roll (58 × variable mm). Width ≈ 165 pt at 72 ppi.
        /// Height is set per content; default uses 297 mm (≈ 842 pt).
        case receipt58mm

        var sizeInPoints: CGSize {
            switch self {
            case .a4:          return CGSize(width: 595, height: 842)
            case .label:       return CGSize(width: 283, height: 425)
            case .receipt58mm: return CGSize(width: 165, height: 842)
            }
        }
    }

    // MARK: - Single-Item Composite Rendering

    /// Renders a single item using the same 3-column grid layout as the batch
    /// print, placing the item in the left column only.
    static func compositeImage(
        medicineName: String,
        weight: String = "",
        photo: UIImage,
        layout: PageLayout,
        monochrome: Bool = false
    ) -> UIImage? {
        let item = ScannedItem(
            barcode: "",
            medicineName: medicineName,
            weight: weight,
            photo: photo
        )
        return compositeBatchImage(items: [item], monochrome: monochrome)
    }

    // MARK: - Batch Composite Rendering (4 columns × 5 rows, column-major)

    /// Renders multiple scanned items into a single A4 `UIImage` in a 4-column,
    /// 5-row grid. Each cell: medicine name → ID → weight → photo (top-to-bottom).
    /// Items fill vertically first (column by column).
    static func compositeBatchImage(items: [ScannedItem], monochrome: Bool = false) -> UIImage? {
        guard !items.isEmpty else { return nil }

        let pageSize = PageLayout.a4.sizeInPoints
        let margin: CGFloat = 16
        let headerHeight: CGFloat = 36
        let cellGap: CGFloat = 6
        let columns = 4
        let maxRows = 5

        let renderer = UIGraphicsImageRenderer(size: pageSize)

        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: pageSize))

            // Header
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "ja_JP")
            dateFormatter.dateFormat = "yyyy年MM月dd日 HH:mm"
            let dateString = dateFormatter.string(from: Date())

            let headerAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 12),
                .foregroundColor: UIColor.black,
            ]
            let headerText = "お薬一覧（\(items.count)件）  \(dateString)" as NSString
            headerText.draw(
                at: CGPoint(x: margin, y: margin),
                withAttributes: headerAttributes
            )

            // Separator line
            let separatorY = margin + headerHeight - 6
            UIColor.lightGray.setStroke()
            let separatorPath = UIBezierPath()
            separatorPath.move(to: CGPoint(x: margin, y: separatorY))
            separatorPath.addLine(to: CGPoint(x: pageSize.width - margin, y: separatorY))
            separatorPath.lineWidth = 0.5
            separatorPath.stroke()

            // Grid cells
            let gridTop = margin + headerHeight
            let totalGapX = cellGap * CGFloat(columns - 1)
            let availableWidth = pageSize.width - margin * 2 - totalGapX
            let cellWidth = availableWidth / CGFloat(columns)
            let totalGapY = cellGap * CGFloat(maxRows - 1)
            let availableHeight = pageSize.height - gridTop - margin
            let cellHeight = (availableHeight - totalGapY) / CGFloat(maxRows)

            // Font sizes: name is small, ID and weight are compact
            let nameFontSize: CGFloat = min(8, cellHeight * 0.06)
            let idFontSize: CGFloat = min(7, cellHeight * 0.05)
            let weightFontSize: CGFloat = min(8, cellHeight * 0.06)
            let nameFont = UIFont.boldSystemFont(ofSize: nameFontSize)
            let idFont = UIFont.monospacedDigitSystemFont(ofSize: idFontSize, weight: .medium)
            let weightFont = UIFont.monospacedDigitSystemFont(ofSize: weightFontSize, weight: .bold)

            let nameAttributes: [NSAttributedString.Key: Any] = [
                .font: nameFont,
                .foregroundColor: UIColor.black,
            ]
            let idAttributes: [NSAttributedString.Key: Any] = [
                .font: idFont,
                .foregroundColor: UIColor.systemBlue,
            ]
            let weightAttributes: [NSAttributedString.Key: Any] = [
                .font: weightFont,
                .foregroundColor: UIColor.darkGray,
            ]

            for (index, item) in items.enumerated() {
                // Column-major order: fill vertically first
                let row = index % maxRows
                let col = index / maxRows

                guard col < columns else { break }

                let cellX = margin + CGFloat(col) * (cellWidth + cellGap)
                let cellY = gridTop + CGFloat(row) * (cellHeight + cellGap)

                // Cell background
                let cellRect = CGRect(x: cellX, y: cellY, width: cellWidth, height: cellHeight)
                UIColor(white: 0.95, alpha: 1).setFill()
                let cellPath = UIBezierPath(roundedRect: cellRect, cornerRadius: 4)
                cellPath.fill()

                let textPadding: CGFloat = 4
                var cursorY = cellY + textPadding

                // 1. Medicine name (top)
                let nameRect = CGRect(
                    x: cellX + textPadding,
                    y: cursorY,
                    width: cellWidth - textPadding * 2,
                    height: nameFont.lineHeight + 2
                )
                (item.medicineName as NSString).draw(
                    in: nameRect,
                    withAttributes: nameAttributes
                )
                cursorY += nameFont.lineHeight + 2

                // 2. ScanID (below name)
                if let scanID = item.scanID {
                    let idStr = String(format: "#%06d", scanID) as NSString
                    idStr.draw(
                        at: CGPoint(x: cellX + textPadding, y: cursorY),
                        withAttributes: idAttributes
                    )
                    cursorY += idFont.lineHeight + 1
                }

                // 3. Weight (below ID)
                if !item.weight.isEmpty {
                    let weightText = "\(item.weight)g" as NSString
                    weightText.draw(
                        at: CGPoint(x: cellX + textPadding, y: cursorY),
                        withAttributes: weightAttributes
                    )
                }
                cursorY += weightFont.lineHeight + 2

                // 4. Photo (fill remaining space)
                let photoAvailableWidth = cellWidth - textPadding * 2
                let photoAvailableHeight = cellHeight - (cursorY - cellY) - textPadding

                guard photoAvailableHeight > 0 else { continue }

                let cellPhoto = monochrome ? item.photo.monochromed() : item.photo
                let photoAspect = cellPhoto.size.width / cellPhoto.size.height
                var photoWidth = photoAvailableWidth
                var photoHeight = photoWidth / photoAspect

                if photoHeight > photoAvailableHeight {
                    photoHeight = photoAvailableHeight
                    photoWidth = photoHeight * photoAspect
                }

                let photoX = cellX + textPadding + (photoAvailableWidth - photoWidth) / 2
                let photoRect = CGRect(x: photoX, y: cursorY,
                                       width: photoWidth, height: photoHeight)

                let photoClipPath = UIBezierPath(roundedRect: photoRect, cornerRadius: 3)
                context.cgContext.saveGState()
                photoClipPath.addClip()
                cellPhoto.draw(in: photoRect)
                context.cgContext.restoreGState()
            }
        }
    }

    // MARK: - Journal (Receipt-style) Print

    /// Renders a receipt/journal-style list from history records.
    /// Columns: 日付 | 撮影ID | 医薬品名 | 秤量数
    /// `layout`: `.a4` for normal A4, `.receipt58mm` for CT-S251 58mm receipt printer.
    static func journalImage(records: [HistoryRecord], layout: PageLayout = .a4) -> UIImage? {
        guard !records.isEmpty else { return nil }

        switch layout {
        case .receipt58mm:
            return journalReceiptImage(records: records)
        default:
            return journalA4Image(records: records)
        }
    }

    // MARK: Journal – A4

    private static func journalA4Image(records: [HistoryRecord]) -> UIImage {
        let pageSize = PageLayout.a4.sizeInPoints
        let margin: CGFloat = 24
        let renderer = UIGraphicsImageRenderer(size: pageSize)

        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: pageSize))

            let titleFont = UIFont.boldSystemFont(ofSize: 18)
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.black,
            ]

            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "ja_JP")
            dateFormatter.dateFormat = "yyyy年MM月dd日 HH:mm"
            let now = dateFormatter.string(from: Date())

            let title = "秤量ジャーナル  \(now)" as NSString
            title.draw(at: CGPoint(x: margin, y: margin), withAttributes: titleAttributes)

            let titleBottom = margin + titleFont.lineHeight + 8

            let headerFont = UIFont.boldSystemFont(ofSize: 11)
            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: headerFont,
                .foregroundColor: UIColor.darkGray,
            ]

            let colDate: CGFloat = margin
            let colID: CGFloat = margin + 120
            let colName: CGFloat = margin + 190
            let colWeight: CGFloat = pageSize.width - margin - 60

            for (x, text) in [(colDate, "日付"), (colID, "撮影ID"), (colName, "医薬品名"), (colWeight, "秤量(g)")] {
                (text as NSString).draw(at: CGPoint(x: x, y: titleBottom), withAttributes: headerAttrs)
            }

            let sepY = titleBottom + headerFont.lineHeight + 4
            UIColor.black.setStroke()
            let sepPath = UIBezierPath()
            sepPath.move(to: CGPoint(x: margin, y: sepY))
            sepPath.addLine(to: CGPoint(x: pageSize.width - margin, y: sepY))
            sepPath.lineWidth = 1.0
            sepPath.stroke()

            let rowFont = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            let nameFont = UIFont.systemFont(ofSize: 10)
            let rowAttrs: [NSAttributedString.Key: Any] = [.font: rowFont, .foregroundColor: UIColor.black]
            let nameAttrs: [NSAttributedString.Key: Any] = [.font: nameFont, .foregroundColor: UIColor.black]

            let rowDateFormatter = DateFormatter()
            rowDateFormatter.locale = Locale(identifier: "ja_JP")
            rowDateFormatter.dateFormat = "M/d HH:mm"

            let rowHeight: CGFloat = rowFont.lineHeight + 6
            var y = sepY + 6
            let sorted = records.sorted { $0.date < $1.date }

            for record in sorted {
                if y + rowHeight > pageSize.height - margin { break }

                (rowDateFormatter.string(from: record.date) as NSString)
                    .draw(at: CGPoint(x: colDate, y: y), withAttributes: rowAttrs)
                (record.scanIDString as NSString)
                    .draw(at: CGPoint(x: colID, y: y), withAttributes: rowAttrs)
                (record.medicineName as NSString).draw(
                    in: CGRect(x: colName, y: y, width: colWeight - colName - 8, height: rowHeight),
                    withAttributes: nameAttrs)
                ((record.weight.isEmpty ? "-" : record.weight) as NSString)
                    .draw(at: CGPoint(x: colWeight, y: y), withAttributes: rowAttrs)

                let rowSepY = y + rowHeight - 1
                UIColor(white: 0.85, alpha: 1).setStroke()
                let rowSep = UIBezierPath()
                rowSep.move(to: CGPoint(x: margin, y: rowSepY))
                rowSep.addLine(to: CGPoint(x: pageSize.width - margin, y: rowSepY))
                rowSep.lineWidth = 0.5
                rowSep.stroke()

                y += rowHeight
            }

            y += 8
            let footerFont = UIFont.boldSystemFont(ofSize: 11)
            let footerAttrs: [NSAttributedString.Key: Any] = [.font: footerFont, .foregroundColor: UIColor.black]
            ("合計: \(records.count)件" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: footerAttrs)
        }
    }

    // MARK: Journal – Receipt (58mm / CT-S251)

    private static func journalReceiptImage(records: [HistoryRecord]) -> UIImage {
        // 58mm ≈ 165pt at 72ppi. Calculate height based on content.
        let pageWidth: CGFloat = 165
        let margin: CGFloat = 6
        let contentWidth = pageWidth - margin * 2

        // Pre-calculate height
        let titleFontSize: CGFloat = 9
        let rowFontSize: CGFloat = 7
        let titleFont = UIFont.boldSystemFont(ofSize: titleFontSize)
        let rowFont = UIFont.systemFont(ofSize: rowFontSize)
        let rowHeight: CGFloat = rowFont.lineHeight * 2 + 6   // 2 lines per item
        let headerArea: CGFloat = titleFont.lineHeight + 20 + rowFont.lineHeight + 8
        let footerArea: CGFloat = 30
        let totalHeight = headerArea + rowHeight * CGFloat(records.count) + footerArea

        let pageSize = CGSize(width: pageWidth, height: max(totalHeight, 100))
        let renderer = UIGraphicsImageRenderer(size: pageSize)

        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: pageSize))

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.black,
            ]

            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "ja_JP")
            dateFormatter.dateFormat = "yyyy/MM/dd HH:mm"
            let now = dateFormatter.string(from: Date())

            // Title
            ("秤量ジャーナル" as NSString).draw(at: CGPoint(x: margin, y: margin), withAttributes: titleAttrs)
            var y = margin + titleFont.lineHeight + 2

            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 7),
                .foregroundColor: UIColor.darkGray,
            ]
            (now as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: subAttrs)
            y += rowFont.lineHeight + 4

            // Separator
            UIColor.black.setStroke()
            let sep = UIBezierPath()
            sep.move(to: CGPoint(x: margin, y: y))
            sep.addLine(to: CGPoint(x: pageWidth - margin, y: y))
            sep.lineWidth = 0.5
            sep.stroke()
            y += 4

            // Rows – 2-line format for narrow receipt:
            // Line 1: ID   date   weight
            // Line 2: medicine name
            let idFont = UIFont.monospacedDigitSystemFont(ofSize: rowFontSize, weight: .medium)
            let nameFont = UIFont.systemFont(ofSize: rowFontSize)
            let idAttrs: [NSAttributedString.Key: Any] = [.font: idFont, .foregroundColor: UIColor.black]
            let nameAttrs: [NSAttributedString.Key: Any] = [.font: nameFont, .foregroundColor: UIColor.black]

            let rowDateFormatter = DateFormatter()
            rowDateFormatter.locale = Locale(identifier: "ja_JP")
            rowDateFormatter.dateFormat = "M/d HH:mm"

            let sorted = records.sorted { $0.date < $1.date }

            for record in sorted {
                // Line 1: #ID  date  weight
                let line1Left = "#\(record.scanIDString) \(rowDateFormatter.string(from: record.date))"
                let weightStr = record.weight.isEmpty ? "" : "\(record.weight)g"

                (line1Left as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: idAttrs)

                if !weightStr.isEmpty {
                    let wSize = (weightStr as NSString).size(withAttributes: idAttrs)
                    (weightStr as NSString).draw(
                        at: CGPoint(x: pageWidth - margin - wSize.width, y: y),
                        withAttributes: idAttrs)
                }
                y += idFont.lineHeight + 1

                // Line 2: medicine name
                (record.medicineName as NSString).draw(
                    in: CGRect(x: margin + 4, y: y, width: contentWidth - 4, height: nameFont.lineHeight + 2),
                    withAttributes: nameAttrs)
                y += nameFont.lineHeight + 4

                // Dotted separator
                UIColor(white: 0.7, alpha: 1).setStroke()
                let dotSep = UIBezierPath()
                dotSep.move(to: CGPoint(x: margin, y: y))
                dotSep.addLine(to: CGPoint(x: pageWidth - margin, y: y))
                dotSep.lineWidth = 0.3
                dotSep.setLineDash([2, 2], count: 2, phase: 0)
                dotSep.stroke()
                y += 2
            }

            // Footer
            y += 4
            let footerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 8),
                .foregroundColor: UIColor.black,
            ]
            ("合計: \(records.count)件" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: footerAttrs)
        }
    }

    // MARK: - PDF Generation (alternative)

    static func compositePDF(
        medicineName: String,
        weight: String = "",
        photo: UIImage,
        layout: PageLayout,
        monochrome: Bool = false
    ) -> Data? {
        guard let image = compositeImage(
            medicineName: medicineName,
            weight: weight,
            photo: photo,
            layout: layout,
            monochrome: monochrome
        ) else { return nil }

        let pageSize = layout.sizeInPoints
        let pdfRenderer = UIGraphicsPDFRenderer(
            bounds: CGRect(origin: .zero, size: pageSize)
        )

        return pdfRenderer.pdfData { ctx in
            ctx.beginPage()
            image.draw(in: CGRect(origin: .zero, size: pageSize))
        }
    }
}
