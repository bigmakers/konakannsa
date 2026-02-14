import AVFoundation
import SwiftUI

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

    /// Controls navigation to the confirmation screen.
    @Published var showConfirmation = false

    /// User-facing error message (camera permission denied, etc.).
    @Published var errorMessage: String?

    /// Whether scanning is currently active.
    @Published var isScanningActive = true

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

    /// Resets state so the user can scan another barcode.
    func resetScan() {
        medicineName = nil
        scannedBarcode = nil
        capturedPhoto = nil
        showConfirmation = false
        isScanningActive = true
    }
}
