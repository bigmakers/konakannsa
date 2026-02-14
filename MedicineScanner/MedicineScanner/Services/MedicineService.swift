import Foundation

/// Service that maps barcode strings to medicine names.
/// Uses a hardcoded dictionary for prototype/testing purposes.
struct MedicineService {

    // MARK: - Mock Database

    /// EAN-13 (JAN) barcodes mapped to medicine names.
    /// Add or modify entries here to expand the test dataset.
    private static let database: [String: String] = [
        // — Common OTC medicines (fictional JAN codes) —
        "4987123456789": "ロキソニンS 12錠",
        "4987234567890": "バファリンA 20錠",
        "4987345678901": "パブロンゴールドA 44錠",
        "4987456789012": "アレグラFX 28錠",
        "4987567890123": "ガスター10 12錠",
        "4987678901234": "イブクイック頭痛薬 20錠",
        "4987789012345": "ムヒアルファEX",
        "4987890123456": "ビオフェルミンS 45錠",
        "4987901234567": "太田胃散 75g",
        "4987012345678": "新ルルAゴールドDX 30錠",

        // — Additional entries for testing —
        "4912345678904": "アリナミンEXプラス 60錠",
        "4901234567894": "サロンパスAe 140枚",
    ]

    // MARK: - Lookup

    /// Look up a medicine name by its barcode string.
    /// - Parameter barcode: The scanned barcode value (e.g. EAN-13 digits).
    /// - Returns: The medicine name if found, otherwise `nil`.
    static func medicineName(for barcode: String) -> String? {
        database[barcode]
    }
}
