import Foundation

/// Service that maps barcode strings to medicine names.
/// Built-in entries are supplemented by user-registered entries persisted in UserDefaults.
struct MedicineService {

    // MARK: - Built-in Database

    private static let builtInDatabase: [String: String] = [
        "4987067258017": "アレグラFX 28錠",
        "4987306048485": "パブロンSゴールドW 60錠",
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

    // MARK: - Maintenance

    /// A single medicine entry for list display.
    struct MedicineEntry: Identifiable {
        var id: String { barcode }
        let barcode: String
        let name: String
        let isBuiltIn: Bool
    }

    /// Returns all registered medicines (built-in + user-registered).
    static func allEntries() -> [MedicineEntry] {
        var entries: [MedicineEntry] = []
        for (barcode, name) in builtInDatabase {
            entries.append(MedicineEntry(barcode: barcode, name: name, isBuiltIn: true))
        }
        for (barcode, name) in userDatabase {
            if builtInDatabase[barcode] == nil {
                entries.append(MedicineEntry(barcode: barcode, name: name, isBuiltIn: false))
            }
        }
        return entries.sorted { $0.name < $1.name }
    }

    /// Returns only user-registered entries.
    static func userEntries() -> [MedicineEntry] {
        userDatabase.map { MedicineEntry(barcode: $0.key, name: $0.value, isBuiltIn: false) }
            .sorted { $0.name < $1.name }
    }

    /// Deletes a user-registered entry. Built-in entries cannot be deleted.
    static func delete(barcode: String) {
        var db = userDatabase
        db.removeValue(forKey: barcode)
        userDatabase = db
    }

    /// Updates the name of a user-registered entry, or creates a new user entry
    /// that overrides a built-in one.
    static func update(barcode: String, name: String) {
        register(barcode: barcode, name: name)
    }
}
