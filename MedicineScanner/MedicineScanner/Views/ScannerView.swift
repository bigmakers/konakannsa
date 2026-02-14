import AVFoundation
import SwiftUI

// MARK: - ScannerView (SwiftUI)

/// Home screen that shows the live camera feed, overlays the detected medicine
/// name, and provides a "Take Photo" button once a barcode has been matched.
/// Also supports batch scanning: users can add multiple medicines to a list
/// and print them all together on a single A4 page.
struct ScannerView: View {
    @StateObject private var viewModel = ScannerViewModel()
    @AppStorage("isMonochrome") private var isMonochrome = false
    @AppStorage("cameraZoom") private var cameraZoom: Double = 2.0
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Live camera preview + barcode scanner
                CameraPreview(viewModel: viewModel, zoomFactor: cameraZoom)
                    .ignoresSafeArea()
                    .saturation(isMonochrome ? 0 : 1)
                    .contrast(isMonochrome ? 1.3 : 1)

                // Overlay UI
                VStack {
                    // Theme toggle (top-left) + Batch count badge (top-right)
                    HStack {
                        Button {
                            isMonochrome.toggle()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isMonochrome
                                      ? "circle.lefthalf.filled"
                                      : "paintpalette.fill")
                                Text(isMonochrome ? "白黒" : "カラー")
                                    .fontWeight(.semibold)
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                        }
                        .padding(.leading, 16)
                        .padding(.top, 8)

                        Spacer()
                        if !viewModel.scannedItems.isEmpty {
                            Button {
                                viewModel.showBatchConfirmation = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "list.bullet.rectangle.portrait")
                                    Text("\(viewModel.scannedItems.count)件")
                                        .fontWeight(.semibold)
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                            }
                            .padding(.trailing, 16)
                            .padding(.top, 8)
                        }
                    }

                    Spacer()

                    if let name = viewModel.medicineName {
                        // Medicine badge
                        Text(name)
                            .font(.title2.bold())
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .padding(.bottom, 8)

                        // Take Photo button (large)
                        Button {
                            viewModel.isScanningActive = false
                            NotificationCenter.default.post(name: .capturePhoto, object: nil)
                        } label: {
                            Label("撮影する", systemImage: "camera.fill")
                                .font(.title.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                                .background(isMonochrome ? Color.black : Color.accentColor)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                        .padding(.horizontal, 24)
                    } else if let barcode = viewModel.scannedBarcode {
                        Text("未登録: \(barcode)")
                            .font(.subheadline)
                            .padding(10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text("医薬品のバーコードにカメラを向けてください")
                            .font(.subheadline)
                            .padding(10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }

                    // Reset button (visible after a barcode is scanned)
                    if viewModel.scannedBarcode != nil && !viewModel.showConfirmation {
                        Button("もう一度スキャン") {
                            viewModel.resetScan()
                        }
                        .font(.subheadline)
                        .padding(.top, 6)
                    }

                    // "Print all" button when batch list has items
                    if !viewModel.scannedItems.isEmpty && viewModel.medicineName == nil {
                        Button {
                            viewModel.showBatchConfirmation = true
                        } label: {
                            Label(
                                "まとめて印刷（\(viewModel.scannedItems.count)件）",
                                systemImage: "printer.fill"
                            )
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isMonochrome ? Color.black : Color.orange)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 40)
                        .padding(.top, 12)
                    }
                }
                .padding(.bottom, 40)
            }
            .navigationTitle("お薬スキャナー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        NavigationLink {
                            HistoryView()
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        MedicineListView()
                    } label: {
                        Image(systemName: "list.bullet.clipboard")
                    }
                }
            }
            .alert("エラー", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert("未登録のバーコード", isPresented: $viewModel.showRegistrationAlert) {
                TextField("薬品名を入力", text: $viewModel.registrationName)
                Button("登録") {
                    viewModel.registerCurrentBarcode()
                }
                Button("スキップ", role: .cancel) {
                    viewModel.resetScan()
                }
            } message: {
                Text("バーコード「\(viewModel.scannedBarcode ?? "")」は未登録です。薬品名を入力して登録しますか？")
            }
            .navigationDestination(isPresented: $viewModel.showConfirmation) {
                if let photo = viewModel.capturedPhoto,
                   let name = viewModel.medicineName {
                    ConfirmationView(
                        photo: photo,
                        medicineName: name,
                        weight: $viewModel.recognizedWeight,
                        isMonochrome: isMonochrome,
                        batchCount: viewModel.scannedItems.count,
                        onAddToList: {
                            viewModel.addToListAndContinue()
                        },
                        onRetake: {
                            viewModel.retakePhoto()
                        }
                    ) {
                        viewModel.resetScan()
                    }
                }
            }
            .navigationDestination(isPresented: $viewModel.showBatchConfirmation) {
                BatchConfirmationView(viewModel: viewModel)
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet(cameraZoom: $cameraZoom)
            }
        }
    }
}

// MARK: - Settings Sheet

struct SettingsSheet: View {
    @Binding var cameraZoom: Double
    @AppStorage("journalLayout") private var journalLayout: String = "a4"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("カメラ設定") {
                    Picker("ズーム倍率", selection: $cameraZoom) {
                        Text("1x").tag(1.0)
                        Text("2x").tag(2.0)
                    }
                    .pickerStyle(.segmented)

                    Text("ズーム倍率はアプリを再起動すると反映されます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("ジャーナル印刷") {
                    Picker("用紙サイズ", selection: $journalLayout) {
                        Text("A4").tag("a4")
                        Text("レシート（58mm）").tag("receipt")
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Notification Name

extension Notification.Name {
    /// Posted when the user taps "Take Photo" to trigger a still capture.
    static let capturePhoto = Notification.Name("capturePhoto")
}

// MARK: - CameraPreview (UIViewRepresentable)

/// Wraps an `AVCaptureSession` that performs both barcode detection and still
/// photo capture, bridging the results back to `ScannerViewModel`.
struct CameraPreview: UIViewRepresentable {
    @ObservedObject var viewModel: ScannerViewModel
    var zoomFactor: Double

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        context.coordinator.setupSession(in: view, zoom: zoomFactor)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Resize preview layer when the SwiftUI layout changes.
        DispatchQueue.main.async {
            context.coordinator.previewLayer?.frame = uiView.bounds
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    // MARK: Coordinator

    final class Coordinator: NSObject,
        AVCaptureMetadataOutputObjectsDelegate,
        AVCapturePhotoCaptureDelegate
    {
        let viewModel: ScannerViewModel
        var previewLayer: AVCaptureVideoPreviewLayer?

        private let session = AVCaptureSession()
        private let photoOutput = AVCapturePhotoOutput()
        private let metadataOutput = AVCaptureMetadataOutput()
        private var captureObserver: NSObjectProtocol?

        init(viewModel: ScannerViewModel) {
            self.viewModel = viewModel
            super.init()
        }

        deinit {
            if let observer = captureObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            session.stopRunning()
        }

        func setupSession(in view: UIView, zoom: Double) {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                        for: .video,
                                                        position: .back),
                  let input = try? AVCaptureDeviceInput(device: device)
            else {
                Task { @MainActor in
                    viewModel.errorMessage = "この端末ではカメラを利用できません。"
                }
                return
            }

            session.beginConfiguration()
            session.sessionPreset = .photo

            if session.canAddInput(input) { session.addInput(input) }

            // Metadata (barcode) output
            if session.canAddOutput(metadataOutput) {
                session.addOutput(metadataOutput)
                metadataOutput.setMetadataObjectsDelegate(self, queue: .main)

                // EAN-13 covers JAN codes. Also include GS1 DataBar types
                // supported by AVFoundation (available on iOS 15.4+).
                var types: [AVMetadataObject.ObjectType] = [.ean13, .ean8]
                // GS1 DataBar types if available
                if #available(iOS 15.4, *) {
                    types.append(contentsOf: [
                        .gs1DataBar,
                        .gs1DataBarExpanded,
                        .gs1DataBarLimited,
                    ])
                }
                metadataOutput.metadataObjectTypes = types
            }

            // Still photo output
            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            }

            session.commitConfiguration()

            // Configure zoom and focus AFTER session is committed,
            // because sessionPreset changes reset device settings.
            do {
                try device.lockForConfiguration()

                // Apply user-selected zoom level
                let desiredZoom = CGFloat(zoom)
                device.videoZoomFactor = min(max(desiredZoom, 1.0),
                                             device.activeFormat.videoMaxZoomFactor)

                // Near-field focus priority
                if device.isAutoFocusRangeRestrictionSupported {
                    device.autoFocusRangeRestriction = .near
                }
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }

                device.unlockForConfiguration()
            } catch {
                // Continue even if camera config fails
            }

            // Preview layer
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            previewLayer = layer

            // Start capture session on a background queue.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }

            // Listen for the "Take Photo" notification.
            captureObserver = NotificationCenter.default.addObserver(
                forName: .capturePhoto,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.captureStillPhoto()
            }
        }

        // MARK: Barcode Detection

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            if let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
               let value = readable.stringValue {
                Task { @MainActor in
                    guard viewModel.isScanningActive else { return }
                    viewModel.didDetectBarcode(value)
                }
            }
        }

        // MARK: Photo Capture

        private func captureStillPhoto() {
            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }

        func photoOutput(
            _ output: AVCapturePhotoOutput,
            didFinishProcessingPhoto photo: AVCapturePhoto,
            error: Error?
        ) {
            if let error {
                Task { @MainActor in
                    viewModel.errorMessage = "写真の撮影に失敗しました: \(error.localizedDescription)"
                }
                return
            }
            guard let data = photo.fileDataRepresentation(),
                  let image = UIImage(data: data)
            else { return }

            Task { @MainActor in
                viewModel.didCapturePhoto(image)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ScannerView()
}
