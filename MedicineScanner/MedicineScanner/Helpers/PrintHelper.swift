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

        var sizeInPoints: CGSize {
            switch self {
            case .a4:    return CGSize(width: 595, height: 842)
            case .label: return CGSize(width: 283, height: 425)
            }
        }
    }

    // MARK: - Single-Item Composite Rendering

    static func compositeImage(
        medicineName: String,
        weight: String = "",
        photo: UIImage,
        layout: PageLayout,
        monochrome: Bool = false
    ) -> UIImage? {
        let processedPhoto = monochrome ? photo.monochromed() : photo
        let pageSize = layout.sizeInPoints
        let margin: CGFloat = 30
        let textTopPadding: CGFloat = 40
        let textToImageGap: CGFloat = 20

        let renderer = UIGraphicsImageRenderer(size: pageSize)

        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: pageSize))

            let maxTextWidth = pageSize.width - margin * 2

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: layout == .a4 ? 40 : 26),
                .foregroundColor: UIColor.black,
            ]

            // Build title with weight
            let titleText = weight.isEmpty ? medicineName : "\(medicineName)　\(weight)g"

            let titleBounds = (titleText as NSString).boundingRect(
                with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: titleAttributes,
                context: nil
            )

            (titleText as NSString).draw(
                in: CGRect(
                    x: margin,
                    y: textTopPadding,
                    width: maxTextWidth,
                    height: titleBounds.height
                ),
                withAttributes: titleAttributes
            )

            // Date / timestamp
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "ja_JP")
            dateFormatter.dateFormat = "yyyy年MM月dd日 HH:mm"
            let dateString = dateFormatter.string(from: Date())

            let dateAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: layout == .a4 ? 14 : 10),
                .foregroundColor: UIColor.darkGray,
            ]

            let dateY = textTopPadding + titleBounds.height + 4
            (dateString as NSString).draw(
                at: CGPoint(x: margin, y: dateY),
                withAttributes: dateAttributes
            )

            let dateBounds = (dateString as NSString).size(withAttributes: dateAttributes)

            // Photo
            let imageTopY = dateY + dateBounds.height + textToImageGap
            let availableWidth = pageSize.width - margin * 2
            let availableHeight = pageSize.height - imageTopY - margin

            guard availableHeight > 0, availableWidth > 0 else { return }

            let imageAspect = photo.size.width / photo.size.height
            var drawWidth = availableWidth
            var drawHeight = drawWidth / imageAspect

            if drawHeight > availableHeight {
                drawHeight = availableHeight
                drawWidth = drawHeight * imageAspect
            }

            let drawX = margin + (availableWidth - drawWidth) / 2
            let imageRect = CGRect(x: drawX, y: imageTopY,
                                   width: drawWidth, height: drawHeight)

            processedPhoto.draw(in: imageRect)
        }
    }

    // MARK: - Batch Composite Rendering (3 columns)

    /// Renders multiple scanned items into a single A4 `UIImage` in a 3-column
    /// grid layout. Each cell contains: medicine name + weight (top), photo (below).
    static func compositeBatchImage(items: [ScannedItem], monochrome: Bool = false) -> UIImage? {
        guard !items.isEmpty else { return nil }

        let pageSize = PageLayout.a4.sizeInPoints
        let margin: CGFloat = 20
        let headerHeight: CGFloat = 44
        let cellGap: CGFloat = 10
        let columns = 3

        let rows = (items.count + columns - 1) / columns

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
                .font: UIFont.boldSystemFont(ofSize: 16),
                .foregroundColor: UIColor.black,
            ]
            let headerText = "お薬一覧（\(items.count)件）  \(dateString)" as NSString
            headerText.draw(
                at: CGPoint(x: margin, y: margin),
                withAttributes: headerAttributes
            )

            // Separator line
            let separatorY = margin + headerHeight - 8
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
            let totalGapY = cellGap * max(CGFloat(rows - 1), 0)
            let availableHeight = pageSize.height - gridTop - margin
            let cellHeight = (availableHeight - totalGapY) / CGFloat(max(rows, 1))

            let nameFontSize: CGFloat = min(16, cellHeight * 0.12)
            let weightFontSize: CGFloat = min(15, cellHeight * 0.11)
            let nameFont = UIFont.boldSystemFont(ofSize: nameFontSize)
            let weightFont = UIFont.monospacedDigitSystemFont(ofSize: weightFontSize, weight: .bold)

            let nameAttributes: [NSAttributedString.Key: Any] = [
                .font: nameFont,
                .foregroundColor: UIColor.black,
            ]
            let weightAttributes: [NSAttributedString.Key: Any] = [
                .font: weightFont,
                .foregroundColor: UIColor.darkGray,
            ]

            for (index, item) in items.enumerated() {
                let col = index % columns
                let row = index / columns

                let cellX = margin + CGFloat(col) * (cellWidth + cellGap)
                let cellY = gridTop + CGFloat(row) * (cellHeight + cellGap)

                // Cell background
                let cellRect = CGRect(x: cellX, y: cellY, width: cellWidth, height: cellHeight)
                UIColor(white: 0.95, alpha: 1).setFill()
                let cellPath = UIBezierPath(roundedRect: cellRect, cornerRadius: 6)
                cellPath.fill()

                let textPadding: CGFloat = 6

                // Medicine name (top of cell)
                let nameRect = CGRect(
                    x: cellX + textPadding,
                    y: cellY + textPadding,
                    width: cellWidth - textPadding * 2,
                    height: nameFont.lineHeight * 2
                )
                (item.medicineName as NSString).draw(
                    in: nameRect,
                    withAttributes: nameAttributes
                )

                // Weight (below name)
                let weightY = cellY + textPadding + nameFont.lineHeight * 2 + 2
                if !item.weight.isEmpty {
                    let weightText = "\(item.weight)g" as NSString
                    weightText.draw(
                        at: CGPoint(x: cellX + textPadding, y: weightY),
                        withAttributes: weightAttributes
                    )
                }

                // Photo (below weight)
                let photoTop = weightY + weightFont.lineHeight + 4
                let photoAvailableWidth = cellWidth - textPadding * 2
                let photoAvailableHeight = cellHeight - (photoTop - cellY) - textPadding

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
                let photoRect = CGRect(x: photoX, y: photoTop,
                                       width: photoWidth, height: photoHeight)

                let photoClipPath = UIBezierPath(roundedRect: photoRect, cornerRadius: 4)
                context.cgContext.saveGState()
                photoClipPath.addClip()
                cellPhoto.draw(in: photoRect)
                context.cgContext.restoreGState()
            }
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
