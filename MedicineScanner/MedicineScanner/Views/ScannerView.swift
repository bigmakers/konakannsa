import AVFoundation
import SwiftUI

// MARK: - ScannerView (SwiftUI)

/// Home screen that shows the live camera feed, overlays the detected medicine
/// name, and provides a "Take Photo" button once a barcode has been matched.
/// Also supports batch scanning: users can add multiple medicines to a list
/// and print them all together on a single A4 page.
struct ScannerView: View {
    @StateObject private var viewModel = ScannerViewModel()
    @StateObject private var store = StoreManager.shared
    @AppStorage("isMonochrome") private var isMonochrome = false
    @AppStorage("cameraZoom") private var cameraZoom: Double = 2.0
    @State private var showSettings = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Live camera preview + barcode scanner
                CameraPreview(viewModel: viewModel, zoomFactor: cameraZoom)
                    .ignoresSafeArea()
                    .saturation(isMonochrome ? 0 : 1)
                    .contrast(isMonochrome ? 1.3 : 1)

                // Overlay UI
                VStack(spacing: 0) {
                    // Top bar: batch count badge
                    HStack(spacing: 8) {
                        Spacer()

                        // Batch count badge
                        if !viewModel.scannedItems.isEmpty {
                            Button {
                                viewModel.showBatchConfirmation = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "list.bullet.rectangle.portrait")
                                        .font(.caption)
                                    Text("\(viewModel.scannedItems.count)件")
                                        .font(.caption.bold())
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(.white)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    Spacer()

                    if let name = viewModel.medicineName {
                        // Medicine badge
                        Text(name)
                            .font(.title3.bold())
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(.white)
                            .padding(.bottom, 8)

                        // Take Photo button
                        Button {
                            viewModel.isScanningActive = false
                            NotificationCenter.default.post(name: .capturePhoto, object: nil)
                        } label: {
                            Label("撮影する", systemImage: "camera.fill")
                                .font(.title2.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .background(isMonochrome ? Color.black : Color.accentColor)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .padding(.horizontal, 24)
                    } else if let barcode = viewModel.scannedBarcode {
                        Text("未登録: \(barcode)")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.white)
                    } else {
                        Text("医薬品のバーコードにカメラを向けてください")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.white)
                    }

                    // Reset button
                    if viewModel.scannedBarcode != nil && !viewModel.showConfirmation {
                        Button("もう一度スキャン") {
                            viewModel.resetScan()
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
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
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(isMonochrome ? Color.black : Color.orange)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .padding(.horizontal, 40)
                        .padding(.top, 12)
                    }
                }
                .padding(.bottom, 40)
            }
            .navigationTitle("鑑査スキャナー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) {
                        NavigationLink {
                            HistoryView()
                        } label: {
                            Label("履歴", systemImage: "clock.arrow.circlepath")
                                .font(.caption)
                        }
                        Button {
                            showSettings = true
                        } label: {
                            Label("設定", systemImage: "gearshape")
                                .font(.caption)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        MedicineListView(store: store)
                    } label: {
                        Label("医薬品", systemImage: "list.bullet.clipboard")
                            .font(.caption)
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
                    if store.canRegisterMore {
                        viewModel.registerCurrentBarcode()
                    } else {
                        viewModel.resetScan()
                        showPaywall = true
                    }
                }
                Button("スキップ", role: .cancel) {
                    viewModel.resetScan()
                }
            } message: {
                if store.canRegisterMore {
                    Text("バーコード「\(viewModel.scannedBarcode ?? "")」は未登録です。薬品名を入力して登録しますか？")
                } else {
                    Text("バーコード「\(viewModel.scannedBarcode ?? "")」は未登録です。\n無料版の登録上限（\(StoreManager.freeLimit)品目）に達しています。")
                }
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
                SettingsSheet(store: store)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(store: store)
            }
        }
    }
}

// MARK: - Settings Sheet

struct SettingsSheet: View {
    @ObservedObject var store: StoreManager
    @AppStorage("isMonochrome") private var isMonochrome = false
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false
    @State private var showManual = false

    var body: some View {
        NavigationStack {
            Form {
                Section("カメラ設定") {
                    Picker("カラーモード", selection: $isMonochrome) {
                        Text("カラー").tag(false)
                        Text("白黒ハイコントラスト").tag(true)
                    }
                    .pickerStyle(.segmented)

                    Text("白黒モードは秤量表示の視認性が向上します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("使い方") {
                    Button {
                        showManual = true
                    } label: {
                        Label("説明書を見る", systemImage: "book.fill")
                    }
                }

                Section("プラン") {
                    HStack {
                        Text("ステータス")
                        Spacer()
                        Text(store.isPremium ? "プレミアム" : "無料")
                            .foregroundStyle(store.isPremium ? .green : .secondary)
                            .font(.subheadline.bold())
                    }
                    if !store.isPremium {
                        let count = MedicineService.userEntries().count
                        HStack {
                            Text("登録数")
                            Spacer()
                            Text("\(count) / \(StoreManager.freeLimit)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Button("プレミアムにアップグレード") {
                            showPaywall = true
                        }
                    }
                    Button("購入を復元") {
                        Task { await store.restore() }
                    }
                    .foregroundStyle(.secondary)
                }

                Section("寄付") {
                    Button("開発を応援する") {
                        showPaywall = true
                    }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(store: store)
            }
            .sheet(isPresented: $showManual) {
                ManualSheet()
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Manual Sheet

struct ManualSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    manualSection(
                        icon: "barcode.viewfinder",
                        title: "バーコードスキャン",
                        steps: [
                            "医薬品のバーコード（JAN/GS1）にカメラを向けます",
                            "自動でバーコードを読み取り、薬品名を表示します",
                            "未登録のバーコードは薬品名を入力して登録できます",
                        ]
                    )

                    manualSection(
                        icon: "hand.tap.fill",
                        title: "タップフォーカス",
                        steps: [
                            "カメラ画面をタップすると、その位置にピントを合わせます",
                            "秤量の数字が読みにくい場合にご利用ください",
                        ]
                    )

                    manualSection(
                        icon: "camera.fill",
                        title: "撮影と秤量入力",
                        steps: [
                            "「撮影する」ボタンで写真を撮影します",
                            "テンキーで秤量値（g）を入力します",
                            "「リストに追加して次へ」で次の薬品をスキャンできます",
                        ]
                    )

                    manualSection(
                        icon: "printer.fill",
                        title: "印刷",
                        steps: [
                            "1件ずつ、またはリストにまとめて印刷できます",
                            "「写真付き印刷」は薬品名・ID・秤量・写真を一覧印刷します",
                            "「ジャーナル印刷」は日付・ID・薬品名・秤量のリストを印刷します",
                            "AirPrint対応プリンターが必要です",
                        ]
                    )

                    manualSection(
                        icon: "clock.arrow.circlepath",
                        title: "履歴",
                        steps: [
                            "過去7日間のスキャン履歴を確認できます",
                            "撮影IDで検索できます",
                            "左スワイプで削除、右スワイプで再印刷ができます",
                        ]
                    )

                    manualSection(
                        icon: "circle.lefthalf.filled",
                        title: "白黒ハイコントラスト",
                        steps: [
                            "設定のカメラ設定から切り替えられます",
                            "秤量表示の読み取り精度が向上します",
                            "印刷時にも白黒で出力されます",
                        ]
                    )
                }
                .padding(20)
            }
            .navigationTitle("説明書")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func manualSection(icon: String, title: String, steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 16, alignment: .trailing)
                        Text(step)
                            .font(.caption)
                    }
                }
            }
            .padding(.leading, 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
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
/// Supports tap-to-focus.
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
        private var device: AVCaptureDevice?

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

            self.device = device

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

            // Tap-to-focus gesture
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            view.addGestureRecognizer(tapGesture)
            view.isUserInteractionEnabled = true

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

        // MARK: Tap to Focus

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let device = device,
                  let previewLayer = previewLayer,
                  let view = gesture.view else { return }

            let point = gesture.location(in: view)
            let focusPoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)

            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = focusPoint
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = focusPoint
                    device.exposureMode = .autoExpose
                }
                device.unlockForConfiguration()
            } catch {}

            // Visual focus indicator
            showFocusIndicator(at: point, in: view)
        }

        private func showFocusIndicator(at point: CGPoint, in view: UIView) {
            let size: CGFloat = 60
            let indicator = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
            indicator.center = point
            indicator.layer.borderColor = UIColor.white.cgColor
            indicator.layer.borderWidth = 1.5
            indicator.backgroundColor = .clear
            view.addSubview(indicator)

            indicator.transform = CGAffineTransform(scaleX: 1.4, y: 1.4)
            indicator.alpha = 0

            UIView.animate(withDuration: 0.15, animations: {
                indicator.transform = .identity
                indicator.alpha = 1
            }) { _ in
                UIView.animate(withDuration: 0.4, delay: 0.6, options: [], animations: {
                    indicator.alpha = 0
                }) { _ in
                    indicator.removeFromSuperview()
                }
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
