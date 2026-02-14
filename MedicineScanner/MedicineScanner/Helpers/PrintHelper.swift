import UIKit

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

    // MARK: - Composite Rendering

    /// Renders the medicine name and photo into a single `UIImage` sized
    /// to the requested page layout.
    ///
    /// The layout places the medicine name at the top of the page followed
    /// by the photo scaled to fit the remaining space with margins.
    ///
    /// - Parameters:
    ///   - medicineName: Text to render at the top of the page.
    ///   - photo: The captured `UIImage` to include.
    ///   - layout: The target page size (`.a4` or `.label`).
    /// - Returns: A rendered `UIImage`, or `nil` if rendering fails.
    static func compositeImage(
        medicineName: String,
        photo: UIImage,
        layout: PageLayout
    ) -> UIImage? {
        let pageSize = layout.sizeInPoints
        let margin: CGFloat = 30
        let textTopPadding: CGFloat = 40
        let textToImageGap: CGFloat = 20

        let renderer = UIGraphicsImageRenderer(size: pageSize)

        return renderer.image { context in
            // White background
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: pageSize))

            // ── Title text ──────────────────────────────────────────────
            let maxTextWidth = pageSize.width - margin * 2

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: layout == .a4 ? 28 : 18),
                .foregroundColor: UIColor.black,
            ]

            let titleRect = CGRect(
                x: margin,
                y: textTopPadding,
                width: maxTextWidth,
                height: .greatestFiniteMagnitude
            )

            let titleBounds = (medicineName as NSString).boundingRect(
                with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: titleAttributes,
                context: nil
            )

            (medicineName as NSString).draw(
                in: CGRect(
                    x: margin,
                    y: textTopPadding,
                    width: titleRect.width,
                    height: titleBounds.height
                ),
                withAttributes: titleAttributes
            )

            // ── Date / timestamp ────────────────────────────────────────
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy/MM/dd HH:mm"
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

            // ── Photo ───────────────────────────────────────────────────
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

            // Center horizontally
            let drawX = margin + (availableWidth - drawWidth) / 2
            let imageRect = CGRect(x: drawX, y: imageTopY,
                                   width: drawWidth, height: drawHeight)

            photo.draw(in: imageRect)
        }
    }

    // MARK: - PDF Generation (alternative)

    /// Generates a PDF `Data` blob with the same composite layout.
    /// Useful if you need to share or archive the printout.
    static func compositePDF(
        medicineName: String,
        photo: UIImage,
        layout: PageLayout
    ) -> Data? {
        guard let image = compositeImage(
            medicineName: medicineName,
            photo: photo,
            layout: layout
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
