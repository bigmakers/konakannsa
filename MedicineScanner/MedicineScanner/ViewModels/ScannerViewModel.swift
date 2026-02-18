import AVFoundation
import SwiftUI

/// A single scanned medicine entry (barcode + name + weight + photo).
struct ScannedItem: Identifiable {
    let id: UUID
    let barcode: String
    let medicineName: String
    var weight: String
    let photo: UIImage
    /// Cropped image of the barcode area captured at detection time.
    let barcodePhoto: UIImage?
    /// Assigned after saving to history (for printing).
    var scanID: Int?

    init(barcode: String, medicineName: String, weight: String, photo: UIImage, barcodePhoto: UIImage?, scanID: Int? = nil) {
        self.id = UUID()
        self.barcode = barcode
        self.medicineName = medicineName
        self.weight = weight
        self.photo = photo
        self.barcodePhoto = barcodePhoto
        self.scanID = scanID
    }

    // MARK: - Temporary Persistence

    /// Directory for batch item photos (uses Application Support for persistence).
    private static var tempDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("BatchItems")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Codable representation for persistence.
    struct Stored: Codable {
        let id: String
        let barcode: String
        let medicineName: String
        let weight: String
        let photoFile: String
        let barcodePhotoFile: String?
    }

    /// Saves photos to temp and returns a Stored struct.
    func toStored() -> Stored {
        let photoFile = "\(id.uuidString)_photo.jpg"
        let photoURL = Self.tempDir.appendingPathComponent(photoFile)
        try? photo.jpegData(compressionQuality: 0.8)?.write(to: photoURL)

        var barcodeFile: String?
        if let bcPhoto = barcodePhoto {
            let name = "\(id.uuidString)_barcode.jpg"
            let url = Self.tempDir.appendingPathComponent(name)
            try? bcPhoto.jpegData(compressionQuality: 0.8)?.write(to: url)
            barcodeFile = name
        }

        return Stored(id: id.uuidString, barcode: barcode, medicineName: medicineName,
                       weight: weight, photoFile: photoFile, barcodePhotoFile: barcodeFile)
    }

    /// Restores a ScannedItem from a Stored struct.
    static func fromStored(_ stored: Stored) -> ScannedItem? {
        let photoURL = tempDir.appendingPathComponent(stored.photoFile)
        guard let photo = UIImage(contentsOfFile: photoURL.path) else { return nil }

        var barcodePhoto: UIImage?
        if let bcFile = stored.barcodePhotoFile {
            barcodePhoto = UIImage(contentsOfFile: tempDir.appendingPathComponent(bcFile).path)
        }

        let item = ScannedItem(barcode: stored.barcode, medicineName: stored.medicineName,
                               weight: stored.weight, photo: photo, barcodePhoto: barcodePhoto)
        // Preserve the original UUID isn't critical; we create a new one via init
        return item
    }

    /// Removes all temp batch item photos.
    static func clearTempFiles() {
        try? FileManager.default.removeItem(at: tempDir)
    }
}

/// Manages the barcode scanning session, medicine lookup, and photo capture flow.
@MainActor
final class ScannerViewModel: ObservableObject {

    // MARK: - Speech

    private let synthesizer = AVSpeechSynthesizer()

    /// Speaks the given text in Japanese.
    private func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    // MARK: - Published State

    /// The medicine name resolved from the last scanned barcode.
    @Published var medicineName: String?

    /// The raw barcode string most recently detected.
    @Published var scannedBarcode: String?

    /// The photo captured by the user after scanning.
    @Published var capturedPhoto: UIImage?

    /// Cropped barcode area photo captured at detection time.
    @Published var barcodePhoto: UIImage?

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

    /// Controls display of the registration alert for unregistered barcodes.
    @Published var showRegistrationAlert = false

    /// Text field binding for the registration alert.
    @Published var registrationName = ""

    /// Manual weight input.
    @Published var recognizedWeight: String = ""

    /// Whether the camera session has been started (home → scanning transition).
    @Published var isCameraStarted = false

    /// Whether the torch (flash) is enabled.
    @Published var isTorchOn = false

    /// Status of barcode area photo capture.
    enum BarcodeCaptureStatus: Equatable {
        case none
        /// Still waiting for a sharp barcode crop.
        case capturing
        /// A barcode crop was successfully captured.
        case captured
        /// Timed out – no usable barcode crop was obtained.
        case failed
    }
    @Published var barcodeCaptureStatus: BarcodeCaptureStatus = .none

    /// Timer used to evaluate barcode crop readiness.
    private var barcodeCaptureTimer: Task<Void, Never>?

    // MARK: - Batch Persistence

    private static let batchKey = "pendingBatchItems"

    /// Saves the current batch list to disk so it survives app termination.
    private func saveBatchToDisk() {
        let stored = scannedItems.map { $0.toStored() }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.batchKey)
        }
    }

    /// Restores a previously saved batch list from disk.
    func restoreBatchFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: Self.batchKey),
              let stored = try? JSONDecoder().decode([ScannedItem.Stored].self, from: data) else { return }
        let items = stored.compactMap { ScannedItem.fromStored($0) }
        if !items.isEmpty {
            scannedItems = items
        }
    }

    /// Removes the persisted batch data.
    private func clearBatchFromDisk() {
        UserDefaults.standard.removeObject(forKey: Self.batchKey)
        ScannedItem.clearTempFiles()
    }

    // MARK: - Barcode Handling

    /// Called by the camera coordinator when a barcode is detected.
    func didDetectBarcode(_ value: String) {
        // Avoid redundant lookups for the same barcode.
        guard value != scannedBarcode else { return }

        scannedBarcode = value
        barcodeCaptureStatus = .capturing
        barcodePhoto = nil

        // Start a timer to check barcode crop readiness
        barcodeCaptureTimer?.cancel()
        barcodeCaptureTimer = Task { [weak self] in
            // Wait 1.5 seconds for a good barcode crop to arrive
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            if self.barcodePhoto != nil {
                self.barcodeCaptureStatus = .captured
            } else {
                self.barcodeCaptureStatus = .failed
            }
        }

        if let name = MedicineService.medicineName(for: value) {
            medicineName = name
            isScanningActive = false
            speak(name)
        } else {
            medicineName = nil
            isScanningActive = false
            showRegistrationAlert = true
            registrationName = ""
        }
    }

    /// Registers the current unregistered barcode with a user-supplied name.
    func registerCurrentBarcode() {
        guard let barcode = scannedBarcode else { return }
        let name = registrationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            resetScan()
            return
        }
        MedicineService.register(barcode: barcode, name: name)
        medicineName = name
        isScanningActive = false
        speak(name)
    }

    /// Called by the camera coordinator when a barcode area image is captured.
    func didCaptureBarcodePhoto(_ image: UIImage) {
        barcodePhoto = image
        // Mark as captured if still waiting
        if barcodeCaptureStatus == .capturing {
            barcodeCaptureStatus = .captured
        }
    }

    /// Called by the camera coordinator when a photo is captured.
    func didCapturePhoto(_ image: UIImage) {
        capturedPhoto = image
        showConfirmation = true
    }

    /// Clears the photo and returns to camera for retake (keeps barcode/name).
    func retakePhoto() {
        capturedPhoto = nil
        showConfirmation = false
    }

    /// Clears only the barcode photo and returns to camera for barcode retake.
    func retakeBarcodePhoto() {
        barcodePhoto = nil
        barcodeCaptureStatus = .failed
        capturedPhoto = nil
        showConfirmation = false
    }

    // MARK: - Batch Management

    /// Adds the current scan result to the batch list and resets for the next scan.
    func addToListAndContinue() {
        guard let barcode = scannedBarcode,
              let name = medicineName,
              let photo = capturedPhoto else { return }

        scannedItems.append(ScannedItem(
            barcode: barcode,
            medicineName: name,
            weight: recognizedWeight,
            photo: photo,
            barcodePhoto: barcodePhoto
        ))
        saveBatchToDisk()
        resetScan()
    }

    /// Removes an item from the batch list.
    func removeItem(_ item: ScannedItem) {
        scannedItems.removeAll { $0.id == item.id }
        saveBatchToDisk()
    }

    /// Resets state so the user can scan another barcode.
    func resetScan() {
        medicineName = nil
        scannedBarcode = nil
        capturedPhoto = nil
        barcodePhoto = nil
        recognizedWeight = ""
        showConfirmation = false
        isScanningActive = true
        barcodeCaptureStatus = .none
        barcodeCaptureTimer?.cancel()
        barcodeCaptureTimer = nil
    }

    /// Clears the entire batch list and resets scanning state.
    /// Returns to the home screen (camera off).
    func resetAll() {
        scannedItems.removeAll()
        clearBatchFromDisk()
        showBatchConfirmation = false
        resetScan()
        isCameraStarted = false
    }

    /// Starts the camera session (transitions from home screen to scanning).
    func startCamera() {
        isCameraStarted = true
        isScanningActive = true
    }

    /// Stops the camera session and returns to the home screen.
    func stopCamera() {
        isCameraStarted = false
        resetScan()
    }
}
