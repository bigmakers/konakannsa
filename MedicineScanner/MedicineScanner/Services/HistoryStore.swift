import UIKit

/// A single history record persisted to disk.
struct HistoryRecord: Codable, Identifiable {
    let id: String          // UUID string
    let barcode: String
    let medicineName: String
    let weight: String
    let photoFileName: String
    let date: Date
    /// Short numeric ID for receipt/journal printing and search.
    let scanID: Int

    /// Returns the full file URL for the stored photo.
    var photoURL: URL {
        HistoryStore.photosDirectory.appendingPathComponent(photoFileName)
    }

    /// Loads the photo from disk (may return nil if file was deleted).
    var photo: UIImage? {
        UIImage(contentsOfFile: photoURL.path)
    }

    /// Formatted scanID for display (zero-padded 6 digits).
    var scanIDString: String {
        String(format: "%06d", scanID)
    }
}

/// Manages scan-history persistence (JSON + photo files).
/// Records older than 7 days are automatically purged on load.
enum HistoryStore {

    // MARK: - Directories

    private static var baseDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScanHistory", isDirectory: true)
    }

    static var photosDirectory: URL {
        baseDirectory.appendingPathComponent("photos", isDirectory: true)
    }

    private static var jsonURL: URL {
        baseDirectory.appendingPathComponent("history.json")
    }

    // MARK: - Retention

    private static let retentionDays: Int = 7

    // MARK: - Public API

    /// Loads all records, purging entries older than 7 days.
    static func loadAll() -> [HistoryRecord] {
        ensureDirectories()
        var records = readJSON()
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        let expired = records.filter { $0.date < cutoff }
        if !expired.isEmpty {
            for record in expired {
                try? FileManager.default.removeItem(at: record.photoURL)
            }
            records.removeAll { $0.date < cutoff }
            writeJSON(records)
        }
        return records.sorted { $0.date > $1.date }
    }

    /// Saves a single scanned item to history.
    static func save(barcode: String, medicineName: String, weight: String, photo: UIImage) {
        ensureDirectories()
        let id = UUID().uuidString
        let fileName = "\(id).jpg"
        let fileURL = photosDirectory.appendingPathComponent(fileName)

        // Save photo as JPEG
        if let data = photo.jpegData(compressionQuality: 0.7) {
            try? data.write(to: fileURL)
        }

        let nextID = nextScanID()

        let record = HistoryRecord(
            id: id,
            barcode: barcode,
            medicineName: medicineName,
            weight: weight,
            photoFileName: fileName,
            date: Date(),
            scanID: nextID
        )

        var records = readJSON()
        records.append(record)
        writeJSON(records)
    }

    /// Saves multiple items at once (batch print).
    static func saveBatch(_ items: [ScannedItem]) {
        for item in items {
            save(barcode: item.barcode, medicineName: item.medicineName, weight: item.weight, photo: item.photo)
        }
    }

    /// Finds a record by its scanID.
    static func find(byScanID scanID: Int) -> HistoryRecord? {
        let records = readJSON()
        return records.first { $0.scanID == scanID }
    }

    /// Deletes a single history record.
    static func delete(_ record: HistoryRecord) {
        try? FileManager.default.removeItem(at: record.photoURL)
        var records = readJSON()
        records.removeAll { $0.id == record.id }
        writeJSON(records)
    }

    /// Deletes all history records.
    static func deleteAll() {
        try? FileManager.default.removeItem(at: baseDirectory)
        ensureDirectories()
    }

    // MARK: - Private Helpers

    private static func ensureDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
    }

    private static func readJSON() -> [HistoryRecord] {
        guard let data = try? Data(contentsOf: jsonURL),
              let records = try? JSONDecoder().decode([HistoryRecord].self, from: data)
        else { return [] }
        return records
    }

    private static func writeJSON(_ records: [HistoryRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: jsonURL, options: .atomic)
    }

    private static func nextScanID() -> Int {
        let records = readJSON()
        let maxID = records.map(\.scanID).max() ?? 0
        return maxID + 1
    }
}
