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

    // MARK: - Barcode Image Generation

    /// Generates a barcode UIImage from a string.
    /// - EAN-13 (13 digits) → uses `CIEAN13BarcodeGenerator` so scanners read it as a standard JAN/EAN barcode.
    /// - GS1 / other → uses `CICode128BarcodeGenerator` (GS1-128 compatible).
    /// Returns nil if the string cannot be encoded.
    static func generateBarcodeImage(from string: String, size: CGSize) -> UIImage? {
        guard !string.isEmpty else { return nil }

        let ciImage: CIImage?

        if string.count == 13, string.allSatisfy(\.isASCII), string.allSatisfy(\.isNumber) {
            // EAN-13 (JAN code) — generate as native EAN-13 barcode
            guard let data = string.data(using: .ascii),
                  let filter = CIFilter(name: "CIEAN13BarcodeGenerator") else { return nil }
            filter.setValue(data, forKey: "inputMessage")
            filter.setValue(0.0, forKey: "inputQuietSpace")
            ciImage = filter.outputImage
        } else {
            // GS1-128 / other — Code128 (universally readable, GS1-128 compatible)
            guard let data = string.data(using: .ascii),
                  let filter = CIFilter(name: "CICode128BarcodeGenerator") else { return nil }
            filter.setValue(data, forKey: "inputMessage")
            filter.setValue(0.0, forKey: "inputQuietSpace")
            ciImage = filter.outputImage
        }

        guard let output = ciImage else { return nil }

        // Scale up to desired size (CIFilter output is tiny)
        let scaleX = size.width / output.extent.width
        let scaleY = size.height / output.extent.height
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - GS1 AI Formatting

    /// Formats a GS1 barcode string by wrapping the first 2 digits (Application
    /// Identifier) in parentheses for human-readable display.
    /// Example: "0104987107610362" → "(01)04987107610362"
    /// Non-GS1 barcodes (e.g. plain EAN-13) are returned unchanged.
    static func formatGS1Display(_ barcode: String) -> String {
        // GS1 DataBar strings are typically longer than 13 digits and start
        // with a 2-digit AI.  Plain EAN-13/EAN-8 are 13 or 8 digits.
        guard barcode.count > 13, barcode.allSatisfy(\.isNumber) else {
            return barcode
        }
        let ai = barcode.prefix(2)
        let rest = barcode.dropFirst(2)
        return "(\(ai))\(rest)"
    }

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
            photo: photo,
            barcodePhoto: nil
        )
        return compositeBatchImage(items: [item], monochrome: monochrome)
    }

    // MARK: - Batch Composite Rendering (4 columns × 5 rows, column-major)

    /// Renders multiple scanned items into a single A4 `UIImage` in a 4-column,
    /// 5-row grid. Each cell: 日付 → ID → 医薬品 → 秤量数 → 写真1(バーコード) → 写真2(秤量).
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

            // Font sizes
            let dateFontSize: CGFloat = min(6, cellHeight * 0.04)
            let nameFontSize: CGFloat = min(8, cellHeight * 0.06)
            let idFontSize: CGFloat = min(7, cellHeight * 0.05)
            let weightFontSize: CGFloat = min(8, cellHeight * 0.06)
            let dateFont = UIFont.monospacedDigitSystemFont(ofSize: dateFontSize, weight: .regular)
            let nameFont = UIFont.boldSystemFont(ofSize: nameFontSize)
            let idFont = UIFont.monospacedDigitSystemFont(ofSize: idFontSize, weight: .medium)
            let weightFont = UIFont.monospacedDigitSystemFont(ofSize: weightFontSize, weight: .bold)

            let dateAttributes: [NSAttributedString.Key: Any] = [
                .font: dateFont,
                .foregroundColor: UIColor.darkGray,
            ]
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

            let rowDateFormatter = DateFormatter()
            rowDateFormatter.locale = Locale(identifier: "ja_JP")
            rowDateFormatter.dateFormat = "M/d HH:mm"

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

                // 1. Date (top)
                let nowStr = rowDateFormatter.string(from: Date()) as NSString
                nowStr.draw(
                    at: CGPoint(x: cellX + textPadding, y: cursorY),
                    withAttributes: dateAttributes
                )
                cursorY += dateFont.lineHeight + 1

                // 2. ScanID
                if let scanID = item.scanID {
                    let idStr = String(format: "#%06d", scanID) as NSString
                    idStr.draw(
                        at: CGPoint(x: cellX + textPadding, y: cursorY),
                        withAttributes: idAttributes
                    )
                    cursorY += idFont.lineHeight + 1
                }

                // 3. Medicine name
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
                cursorY += nameFont.lineHeight + 1

                // 4. Weight
                if !item.weight.isEmpty {
                    let weightText = "\(item.weight)g" as NSString
                    weightText.draw(
                        at: CGPoint(x: cellX + textPadding, y: cursorY),
                        withAttributes: weightAttributes
                    )
                }
                cursorY += weightFont.lineHeight + 2

                // 5 & 6. Photos side by side: 写真1(barcode) | 写真2(scale)
                let photoAvailableWidth = cellWidth - textPadding * 2
                let photoAvailableHeight = cellHeight - (cursorY - cellY) - textPadding

                guard photoAvailableHeight > 0 else { continue }

                let hasBarcodePhoto = item.barcodePhoto != nil
                let photoSlotWidth = hasBarcodePhoto ? (photoAvailableWidth - 2) / 2 : photoAvailableWidth

                // Helper to draw a photo in a given rect
                func drawPhoto(_ image: UIImage, in rect: CGRect) {
                    let img = monochrome ? image.monochromed() : image
                    let aspect = img.size.width / img.size.height
                    var w = rect.width
                    var h = w / aspect
                    if h > rect.height {
                        h = rect.height
                        w = h * aspect
                    }
                    let x = rect.origin.x + (rect.width - w) / 2
                    let y = rect.origin.y + (rect.height - h) / 2
                    let drawRect = CGRect(x: x, y: y, width: w, height: h)
                    let clip = UIBezierPath(roundedRect: drawRect, cornerRadius: 3)
                    context.cgContext.saveGState()
                    clip.addClip()
                    img.draw(in: drawRect)
                    context.cgContext.restoreGState()
                }

                if let bcPhoto = item.barcodePhoto {
                    // Photo 1: barcode (left)
                    let photo1Rect = CGRect(x: cellX + textPadding, y: cursorY,
                                            width: photoSlotWidth, height: photoAvailableHeight)
                    drawPhoto(bcPhoto, in: photo1Rect)

                    // Photo 2: scale photo (right)
                    let photo2Rect = CGRect(x: cellX + textPadding + photoSlotWidth + 2, y: cursorY,
                                            width: photoSlotWidth, height: photoAvailableHeight)
                    drawPhoto(item.photo, in: photo2Rect)
                } else {
                    // Only scale photo (full width)
                    let photoRect = CGRect(x: cellX + textPadding, y: cursorY,
                                           width: photoAvailableWidth, height: photoAvailableHeight)
                    drawPhoto(item.photo, in: photoRect)
                }
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

            let headerFont = UIFont.boldSystemFont(ofSize: 10)
            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: headerFont,
                .foregroundColor: UIColor.darkGray,
            ]

            // 5 columns: 日付 | ID | 医薬品名 | バーコード | 秤量(g)
            let colDate: CGFloat = margin
            let colID: CGFloat = margin + 80
            let colName: CGFloat = margin + 140
            let colBarcode: CGFloat = margin + 290
            let colWeight: CGFloat = pageSize.width - margin - 50

            for (x, text) in [
                (colDate, "日付"),
                (colID, "ID"),
                (colName, "医薬品名"),
                (colBarcode, "バーコード"),
                (colWeight, "秤量(g)")
            ] {
                (text as NSString).draw(at: CGPoint(x: x, y: titleBottom), withAttributes: headerAttrs)
            }

            let sepY = titleBottom + headerFont.lineHeight + 4
            UIColor.black.setStroke()
            let sepPath = UIBezierPath()
            sepPath.move(to: CGPoint(x: margin, y: sepY))
            sepPath.addLine(to: CGPoint(x: pageSize.width - margin, y: sepY))
            sepPath.lineWidth = 1.0
            sepPath.stroke()

            let rowFont = UIFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
            let nameFont = UIFont.systemFont(ofSize: 9)
            let rowAttrs: [NSAttributedString.Key: Any] = [.font: rowFont, .foregroundColor: UIColor.black]
            let nameAttrs: [NSAttributedString.Key: Any] = [.font: nameFont, .foregroundColor: UIColor.black]

            let rowDateFormatter = DateFormatter()
            rowDateFormatter.locale = Locale(identifier: "ja_JP")
            rowDateFormatter.dateFormat = "M/d HH:mm"

            // Row height: barcode image height + number text + padding
            let barcodeImgHeight: CGFloat = 22
            let barcodeNumFontSize: CGFloat = 6
            let barcodeNumFont = UIFont.monospacedDigitSystemFont(ofSize: barcodeNumFontSize, weight: .regular)
            let barcodeNumAttrs: [NSAttributedString.Key: Any] = [.font: barcodeNumFont, .foregroundColor: UIColor.black]
            let rowHeight: CGFloat = barcodeImgHeight + barcodeNumFont.lineHeight + 6
            var y = sepY + 6
            let sorted = records.sorted { $0.date < $1.date }

            // Barcode image column width
            let barcodeColWidth = colWeight - colBarcode - 8

            for record in sorted {
                if y + rowHeight > pageSize.height - margin { break }

                // Vertically center text in row
                let textY = y + (rowHeight - rowFont.lineHeight) / 2 - 2

                (rowDateFormatter.string(from: record.date) as NSString)
                    .draw(at: CGPoint(x: colDate, y: textY), withAttributes: rowAttrs)
                (record.scanIDString as NSString)
                    .draw(at: CGPoint(x: colID, y: textY), withAttributes: rowAttrs)
                (record.medicineName as NSString).draw(
                    in: CGRect(x: colName, y: textY, width: colBarcode - colName - 4, height: rowFont.lineHeight + 2),
                    withAttributes: nameAttrs)

                // Draw barcode image instead of text
                if !record.barcode.isEmpty {
                    let barcodeSize = CGSize(width: barcodeColWidth, height: barcodeImgHeight)
                    // Barcode image uses raw data (no parentheses) for scanner compatibility
                    if let barcodeImg = generateBarcodeImage(from: record.barcode, size: barcodeSize) {
                        barcodeImg.draw(in: CGRect(x: colBarcode, y: y + 1,
                                                    width: barcodeColWidth, height: barcodeImgHeight))
                    }
                    // Display text below uses formatted GS1 with parentheses
                    let displayStr = formatGS1Display(record.barcode) as NSString
                    let numSize = displayStr.size(withAttributes: barcodeNumAttrs)
                    let numX = colBarcode + (barcodeColWidth - numSize.width) / 2
                    displayStr.draw(at: CGPoint(x: numX, y: y + barcodeImgHeight + 1),
                                withAttributes: barcodeNumAttrs)
                }

                ((record.weight.isEmpty ? "-" : record.weight) as NSString)
                    .draw(at: CGPoint(x: colWeight, y: textY), withAttributes: rowAttrs)

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
        let barcodeImgH: CGFloat = 18
        let barcodeNumFontSize: CGFloat = 5
        let barcodeNumFontR = UIFont.monospacedDigitSystemFont(ofSize: barcodeNumFontSize, weight: .regular)
        let rowHeight: CGFloat = rowFont.lineHeight * 2 + barcodeImgH + barcodeNumFontR.lineHeight + 10
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
                y += nameFont.lineHeight + 1

                // Line 3: barcode image + number
                if !record.barcode.isEmpty {
                    let bcWidth = contentWidth - 8
                    let bcSize = CGSize(width: bcWidth, height: barcodeImgH)
                    // Barcode image uses raw data (no parentheses) for scanner compatibility
                    if let bcImg = PrintHelper.generateBarcodeImage(from: record.barcode, size: bcSize) {
                        bcImg.draw(in: CGRect(x: margin + 4, y: y, width: bcWidth, height: barcodeImgH))
                    }
                    y += barcodeImgH + 1
                    // Formatted number below barcode
                    let bcNumAttrs: [NSAttributedString.Key: Any] = [
                        .font: barcodeNumFontR,
                        .foregroundColor: UIColor.darkGray,
                    ]
                    let displayStr = PrintHelper.formatGS1Display(record.barcode) as NSString
                    let numSize = displayStr.size(withAttributes: bcNumAttrs)
                    let numX = margin + 4 + (bcWidth - numSize.width) / 2
                    displayStr.draw(at: CGPoint(x: numX, y: y), withAttributes: bcNumAttrs)
                    y += barcodeNumFontR.lineHeight + 1
                }
                y += 3

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
