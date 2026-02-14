import AVFoundation
import SwiftUI

/// A single scanned medicine entry (barcode + name + photo).
struct ScannedItem: Identifiable {
    let id = UUID()
    let barcode: String
    let medicineName: String
    let photo: UIImage
}

/// Manages the barcode scanning session, medicine lookup, and photo capture flow.
@MainActor
final class ScannerViewModel: ObservableObject {

    // MARK: - Published State

    /// The medicine name resolved from the last scanned barcode.
    @Published var medicineName: String?

    /// The raw barcode string most recently detected.
    @Published var scannedBarcode: String?

    /// The photo captured by the user after scanning.
    @Published var capturedPhoto: UIImage?

    /// Controls navigation to the single-item confirmation screen.
    @Published var showConfirmation = false

    /// Controls navigation to the batch confirmation screen.
    @Published var showBatchConfirmation = false

    /// User-facing error message (camera permission denied, etc.).
    @Published var errorMessage: String?

    /// Whether scanning is currently active.
    @Published var isScanningActive = true

    /// Accumulated list of scanned medicines for batch printing.
    @Published var scannedItems: [ScannedItem] = []

    // MARK: - Barcode Handling

    /// Called by the camera coordinator when a barcode is detected.
    func didDetectBarcode(_ value: String) {
        // Avoid redundant lookups for the same barcode.
        guard value != scannedBarcode else { return }

        scannedBarcode = value

        if let name = MedicineService.medicineName(for: value) {
            medicineName = name
            isScanningActive = false
        } else {
            medicineName = nil
        }
    }

    /// Called by the camera coordinator when a photo is captured.
    func didCapturePhoto(_ image: UIImage) {
        capturedPhoto = image
        showConfirmation = true
    }

    // MARK: - Batch Management

    /// Adds the current scan result to the batch list and resets for the next scan.
    func addToListAndContinue() {
        guard let barcode = scannedBarcode,
              let name = medicineName,
              let photo = capturedPhoto else { return }

        scannedItems.append(ScannedItem(barcode: barcode, medicineName: name, photo: photo))
        resetScan()
    }

    /// Removes an item from the batch list.
    func removeItem(_ item: ScannedItem) {
        scannedItems.removeAll { $0.id == item.id }
    }

    /// Resets state so the user can scan another barcode.
    func resetScan() {
        medicineName = nil
        scannedBarcode = nil
        capturedPhoto = nil
        showConfirmation = false
        isScanningActive = true
    }

    /// Clears the entire batch list and resets scanning state.
    func resetAll() {
        scannedItems.removeAll()
        showBatchConfirmation = false
        resetScan()
    }
}
