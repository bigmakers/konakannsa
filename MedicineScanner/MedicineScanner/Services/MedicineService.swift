import Foundation

/// Service that maps barcode strings to medicine names.
/// Built-in entries are supplemented by user-registered entries persisted in UserDefaults.
struct MedicineService {

    // MARK: - Built-in Database

    private static let builtInDatabase: [String: String] = [
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

        // — Additional entries —
        "4912345678904": "アリナミンEXプラス 60錠",
        "4901234567894": "サロンパスAe 140枚",
        "0114987120449502": "プランルカストDS１０％「タカタ」",
    ]

    // MARK: - User-Registered Entries (persisted)

    private static let userDefaultsKey = "registeredMedicines"

    private static var userDatabase: [String: String] {
        get {
            UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: String] ?? [:]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: userDefaultsKey)
        }
    }

    // MARK: - Lookup

    static func medicineName(for barcode: String) -> String? {
        builtInDatabase[barcode] ?? userDatabase[barcode]
    }

    // MARK: - Registration

    static func register(barcode: String, name: String) {
        var db = userDatabase
        db[barcode] = name
        userDatabase = db
    }
}
