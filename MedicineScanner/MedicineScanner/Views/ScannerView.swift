import AVFoundation
import SwiftUI

// MARK: - ScannerView (SwiftUI)

/// Home screen that shows the live camera feed, overlays the detected medicine
/// name, and provides a "Take Photo" button once a barcode has been matched.
/// Also supports batch scanning: users can add multiple medicines to a list
/// and print them all together on a single A4 page.
struct ScannerView: View {
    var forceHome = false
    @StateObject private var viewModel = ScannerViewModel()
    @StateObject private var store = StoreManager.shared
    @AppStorage("isMonochrome") private var isMonochrome = false
    @AppStorage("cameraZoom") private var cameraZoom: Double = 2.0
    @State private var showSettings = false
    @State private var demoReady = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isCameraStarted {
                    scanningView
                } else {
                    homeView
                }
            }
            .navigationTitle(viewModel.isCameraStarted ? "鑑査スキャナー" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(viewModel.isCameraStarted ? .visible : .automatic, for: .navigationBar)
            .toolbarColorScheme(viewModel.isCameraStarted ? .dark : .light, for: .navigationBar)
            .toolbar {
                if viewModel.isCameraStarted {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            viewModel.stopCamera()
                        } label: {
                            Label("ホーム", systemImage: "house.fill")
                                .font(.caption)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            viewModel.isTorchOn.toggle()
                            NotificationCenter.default.post(
                                name: .toggleTorch,
                                object: nil,
                                userInfo: ["on": viewModel.isTorchOn]
                            )
                        } label: {
                            Label(
                                viewModel.isTorchOn ? "ライトON" : "ライトOFF",
                                systemImage: viewModel.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill"
                            )
                            .font(.caption)
                        }
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
                        store.showPaywall = true
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
                        barcodePhoto: viewModel.barcodePhoto,
                        barcode: viewModel.scannedBarcode ?? "",
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
            .sheet(isPresented: $store.showPaywall) {
                PaywallView(store: store)
            }
            .onAppear {
                viewModel.restoreBatchFromDisk()
                #if targetEnvironment(simulator)
                if !demoReady && !forceHome {
                    demoReady = true
                    viewModel.isCameraStarted = true
                    viewModel.scannedBarcode = "4987107610362"
                    viewModel.medicineName = "プランルカストDS10%"
                    viewModel.isScanningActive = false
                    viewModel.barcodeCaptureStatus = .captured
                }
                #endif
            }
        }
    }

    // MARK: - Home View (Camera Off)

    private var homeView: some View {
        ZStack {
            // Background
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // App title
                    VStack(spacing: 10) {
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 52, weight: .light))
                            .foregroundStyle(.orange)
                            .padding(.top, 32)

                        Text("散剤鑑査記録システム")
                            .font(.title2.bold())
                            .foregroundStyle(.primary)

                        Text("コナモン")
                            .font(.title2.bold())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 8)

                    // Flash toggle — large card style
                    Button {
                        viewModel.isTorchOn.toggle()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: viewModel.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(
                                    viewModel.isTorchOn ? Color.orange : Color.gray.opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                                .foregroundStyle(viewModel.isTorchOn ? .white : .secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("ライト")
                                    .font(.body.bold())
                                    .foregroundStyle(.primary)
                                Text(viewModel.isTorchOn ? "ON — カメラ起動時に点灯します" : "OFF")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: viewModel.isTorchOn ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(viewModel.isTorchOn ? .orange : .secondary.opacity(0.3))
                        }
                        .padding(16)
                        .background(.background, in: RoundedRectangle(cornerRadius: 14))
                        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
                    }
                    .padding(.horizontal, 20)

                    // Navigation buttons — 3-column grid
                    HStack(spacing: 12) {
                        NavigationLink {
                            HistoryView()
                        } label: {
                            homeMenuCard(
                                icon: "clock.arrow.circlepath",
                                title: "履歴",
                                color: .blue
                            )
                        }

                        Button {
                            showSettings = true
                        } label: {
                            homeMenuCard(
                                icon: "gearshape.fill",
                                title: "設定",
                                color: .gray
                            )
                        }

                        NavigationLink {
                            MedicineListView(store: store)
                        } label: {
                            homeMenuCard(
                                icon: "list.bullet.clipboard.fill",
                                title: "医薬品",
                                color: .green
                            )
                        }
                    }
                    .padding(.horizontal, 20)

                    // Batch resume badge
                    if !viewModel.scannedItems.isEmpty {
                        Button {
                            viewModel.isCameraStarted = true
                            viewModel.showBatchConfirmation = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "tray.full.fill")
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                                    .foregroundStyle(.orange)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("途中のバッチ")
                                        .font(.body.bold())
                                        .foregroundStyle(.primary)
                                    Text("\(viewModel.scannedItems.count)件のスキャン済みアイテム")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(16)
                            .background(.background, in: RoundedRectangle(cornerRadius: 14))
                            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
                        }
                        .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 40)
                }
            }

            // Start button — pinned to bottom
            VStack {
                Spacer()
                Button {
                    viewModel.startCamera()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "camera.fill")
                            .font(.title3)
                        Text("鑑査開始")
                            .font(.title3.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
                    .shadow(color: .orange.opacity(0.3), radius: 8, y: 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .background(
                    LinearGradient(
                        colors: [
                            Color(uiColor: .systemGroupedBackground).opacity(0),
                            Color(uiColor: .systemGroupedBackground),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 100)
                    .allowsHitTesting(false),
                    alignment: .bottom
                )
            }
        }
    }

    // MARK: - Home Menu Card

    private func homeMenuCard(icon: String, title: String, color: Color) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 48, height: 48)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(color)

            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }

    // MARK: - Scanning View (Camera On)

    private var scanningView: some View {
        ZStack {
            #if targetEnvironment(simulator)
            // Demo background for screenshots
            Color(white: 0.22).ignoresSafeArea()
            #else
            // Live camera preview + barcode scanner
            CameraPreview(viewModel: viewModel, zoomFactor: cameraZoom)
                .ignoresSafeArea()
                .saturation(isMonochrome ? 0 : 1)
                .contrast(isMonochrome ? 1.3 : 1)
            #endif

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
                        .padding(.bottom, 4)

                    // Barcode capture status indicator
                    barcodeCaptureStatusView
                        .padding(.bottom, 8)

                    // Take Photo button
                    if viewModel.barcodeCaptureStatus == .failed {
                        // Barcode photo failed → force manual barcode capture
                        Button {
                            NotificationCenter.default.post(name: .captureBarcodePhoto, object: nil)
                        } label: {
                            Label("バーコード/外観 撮影", systemImage: "barcode.viewfinder")
                                .font(.title2.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .background(Color.orange)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .padding(.horizontal, 24)
                    } else {
                        // Normal: "秤を撮影" or waiting
                        Button {
                            viewModel.isScanningActive = false
                            NotificationCenter.default.post(name: .capturePhoto, object: nil)
                        } label: {
                            Label(
                                viewModel.barcodeCaptureStatus == .captured
                                    ? "秤を撮影"
                                    : "バーコード写真を取得中…",
                                systemImage: "camera.fill"
                            )
                                .font(.title2.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .background(
                                    viewModel.barcodeCaptureStatus == .captured
                                        ? (isMonochrome ? Color.black : Color.accentColor)
                                        : Color.gray.opacity(0.5)
                                )
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .padding(.horizontal, 24)
                        .disabled(viewModel.barcodeCaptureStatus == .capturing)
                    }
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
                    Button {
                        viewModel.resetScan()
                    } label: {
                        Label(
                            viewModel.barcodeCaptureStatus == .failed
                                ? "再スキャンしてください"
                                : "もう一度スキャン",
                            systemImage: viewModel.barcodeCaptureStatus == .failed
                                ? "arrow.counterclockwise"
                                : "barcode.viewfinder"
                        )
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        viewModel.barcodeCaptureStatus == .failed
                            ? Color.red.opacity(0.7)
                            : Color.black.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
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
    }

    // MARK: - Barcode Capture Status View

    @ViewBuilder
    private var barcodeCaptureStatusView: some View {
        switch viewModel.barcodeCaptureStatus {
        case .none:
            EmptyView()
        case .capturing:
            HStack(spacing: 6) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(0.8)
                Text("バーコード写真を取得中…")
                    .font(.caption.bold())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.white)
        case .captured:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                Text("バーコード記録完了")
                    .font(.caption.bold())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.green.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.white)
            .transition(.opacity.combined(with: .scale))
        case .failed:
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                Text("バーコード写真が取得できません")
                    .font(.caption.bold())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.white)
        }
    }
}

// MARK: - Settings Sheet

struct SettingsSheet: View {
    @ObservedObject var store: StoreManager
    @AppStorage("isMonochrome") private var isMonochrome = false
    @Environment(\.dismiss) private var dismiss
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
                    Button("購入を復元") {
                        Task { await store.restore() }
                    }
                    .foregroundStyle(.secondary)
                }

            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
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
    @State private var expandedSections: Set<String> = ["バーコードスキャン"]

    private let sections: [(icon: String, title: String, steps: [String])] = [
        ("barcode.viewfinder", "バーコードスキャン", [
            "医薬品のバーコード（JAN/GS1）にカメラを向けます",
            "自動でバーコードを読み取り、薬品名を表示します",
            "未登録のバーコードは薬品名を入力して登録できます",
        ]),
        ("hand.tap.fill", "タップフォーカス", [
            "カメラ画面をタップすると、その位置にピントを合わせます",
            "秤量の数字が読みにくい場合にご利用ください",
        ]),
        ("camera.fill", "撮影と秤量入力", [
            "「撮影する」ボタンで写真を撮影します",
            "テンキーで秤量値（g）を入力します",
            "「リストに追加して次へ」で次の薬品をスキャンできます",
        ]),
        ("printer.fill", "印刷", [
            "1件ずつ、またはリストにまとめて印刷できます",
            "「写真付き印刷」は薬品名・ID・秤量・写真を一覧印刷します",
            "「ジャーナル印刷」は日付・ID・薬品名・秤量のリストを印刷します",
            "AirPrint対応プリンターが必要です",
        ]),
        ("clock.arrow.circlepath", "履歴", [
            "過去7日間のスキャン履歴を確認できます",
            "ID・薬品名・バーコードで検索できます",
            "左スワイプで削除、右スワイプで再印刷ができます",
        ]),
        ("circle.lefthalf.filled", "白黒ハイコントラスト", [
            "設定のカメラ設定から切り替えられます",
            "秤量表示の読み取り精度が向上します",
            "印刷時にも白黒で出力されます",
        ]),
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections, id: \.title) { section in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedSections.contains(section.title) },
                            set: { isExpanded in
                                if isExpanded {
                                    expandedSections.insert(section.title)
                                } else {
                                    expandedSections.remove(section.title)
                                }
                            }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(section.steps.enumerated()), id: \.offset) { index, step in
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
                        .padding(.vertical, 4)
                    } label: {
                        Label(section.title, systemImage: section.icon)
                            .font(.subheadline.bold())
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("説明書")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Notification Name

extension Notification.Name {
    /// Posted when the user taps "Take Photo" to trigger a still capture.
    static let capturePhoto = Notification.Name("capturePhoto")
    /// Posted when the user taps "バーコード撮影" to manually capture a barcode photo.
    static let captureBarcodePhoto = Notification.Name("captureBarcodePhoto")
    /// Posted to toggle the torch (flash) on/off.
    static let toggleTorch = Notification.Name("toggleTorch")
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
        #if !targetEnvironment(simulator)
        context.coordinator.setupSession(in: view, zoom: zoomFactor)
        #endif
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
        AVCapturePhotoCaptureDelegate,
        AVCaptureVideoDataOutputSampleBufferDelegate
    {
        let viewModel: ScannerViewModel
        var previewLayer: AVCaptureVideoPreviewLayer?

        private let session = AVCaptureSession()
        private let photoOutput = AVCapturePhotoOutput()
        private let metadataOutput = AVCaptureMetadataOutput()
        private let videoDataOutput = AVCaptureVideoDataOutput()
        private var captureObserver: NSObjectProtocol?
        private var barcodeCaptureObserver: NSObjectProtocol?
        private var torchObserver: NSObjectProtocol?
        private var device: AVCaptureDevice?
        /// When true, the next still photo capture will be used as the barcode photo.
        private var isCapturingBarcodePhoto = false

        /// Latest video frame for barcode region cropping.
        private var latestSampleBuffer: CMSampleBuffer?
        /// Barcode bounds detected by metadata output (in video coordinates).
        private var pendingBarcodeBounds: CGRect?
        /// Best (sharpest) barcode crop found so far.
        private var bestBarcodeCrop: UIImage?
        private var bestBarcodeSharpness: CGFloat = 0
        /// The barcode value we are currently collecting frames for.
        private var collectingForBarcode: String?
        /// CIContext reused across frames.
        private let ciContext = CIContext()

        init(viewModel: ScannerViewModel) {
            self.viewModel = viewModel
            super.init()
        }

        deinit {
            if let observer = captureObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = barcodeCaptureObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = torchObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            // Turn off torch before stopping
            if let device, device.hasTorch, device.torchMode != .off {
                try? device.lockForConfiguration()
                device.torchMode = .off
                device.unlockForConfiguration()
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

            // Video data output for barcode frame capture
            videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoDataQueue"))
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            if session.canAddOutput(videoDataOutput) {
                session.addOutput(videoDataOutput)
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

            // Start capture session on a background queue,
            // then apply initial torch state after session is running.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
                // Session is now running – apply torch on main thread
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let torchOn = self.viewModel.isTorchOn
                    if torchOn, let device = self.device, device.hasTorch {
                        do {
                            try device.lockForConfiguration()
                            device.torchMode = .on
                            device.unlockForConfiguration()
                        } catch {}
                    }
                }
            }

            // Listen for the "Take Photo" notification.
            captureObserver = NotificationCenter.default.addObserver(
                forName: .capturePhoto,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.isCapturingBarcodePhoto = false
                self?.captureStillPhoto()
            }

            // Listen for the "Barcode Photo" notification (manual barcode capture).
            barcodeCaptureObserver = NotificationCenter.default.addObserver(
                forName: .captureBarcodePhoto,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.isCapturingBarcodePhoto = true
                self?.captureStillPhoto()
            }

            // Listen for torch toggle notification.
            torchObserver = NotificationCenter.default.addObserver(
                forName: .toggleTorch,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self, let device = self.device, device.hasTorch else { return }
                let on = (notification.userInfo?["on"] as? Bool) ?? false
                do {
                    try device.lockForConfiguration()
                    device.torchMode = on ? .on : .off
                    device.unlockForConfiguration()
                } catch {}
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

        // MARK: Video Data (for barcode frame capture)

        func captureOutput(
            _ output: AVCaptureOutput,
            didOutput sampleBuffer: CMSampleBuffer,
            from connection: AVCaptureConnection
        ) {
            latestSampleBuffer = sampleBuffer

            // If we have pending barcode bounds, evaluate this frame
            if let bounds = pendingBarcodeBounds {
                evaluateFrame(sampleBuffer, bounds: bounds)
            }
        }

        /// Crops the barcode region and measures sharpness; keeps the best one.
        private func evaluateFrame(_ sampleBuffer: CMSampleBuffer, bounds: CGRect) {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let imageWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
            let imageHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

            // bounds is in normalized video coordinates (0..1).
            // Expand the crop area with padding.
            let padding: CGFloat = 0.05
            let cropX = max(0, bounds.origin.x - padding) * imageWidth
            let cropY = max(0, bounds.origin.y - padding) * imageHeight
            let cropW = min(1, bounds.width + padding * 2) * imageWidth
            let cropH = min(1, bounds.height + padding * 2) * imageHeight

            // CIImage origin is bottom-left, so flip Y
            let flippedY = imageHeight - cropY - cropH

            let cropRect = CGRect(x: cropX, y: flippedY, width: cropW, height: cropH)
                .intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

            guard !cropRect.isEmpty else { return }

            let croppedCI = ciImage.cropped(to: cropRect)
            guard let cgImage = ciContext.createCGImage(croppedCI, from: croppedCI.extent) else { return }

            // Measure sharpness using Laplacian variance
            let sharpness = laplacianVariance(cgImage)

            if sharpness > bestBarcodeSharpness {
                bestBarcodeSharpness = sharpness
                bestBarcodeCrop = UIImage(cgImage: cgImage)

                // Send best-so-far to viewModel immediately
                let img = bestBarcodeCrop!
                Task { @MainActor in
                    viewModel.didCaptureBarcodePhoto(img)
                }
            }
        }

        /// Computes the Laplacian variance of a grayscale image as a sharpness measure.
        /// Higher values = sharper image.
        private func laplacianVariance(_ cgImage: CGImage) -> CGFloat {
            let width = cgImage.width
            let height = cgImage.height
            guard width > 2, height > 2 else { return 0 }

            // Convert to grayscale pixel buffer
            let bytesPerRow = width
            let totalBytes = bytesPerRow * height
            var pixels = [UInt8](repeating: 0, count: totalBytes)

            guard let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return 0 }

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

            // Sample every 4th pixel for speed
            var sum: Double = 0
            var sumSq: Double = 0
            var count: Double = 0
            let step = 4

            for y in stride(from: 1, to: height - 1, by: step) {
                for x in stride(from: 1, to: width - 1, by: step) {
                    let idx = y * bytesPerRow + x
                    // Laplacian: 4*center - top - bottom - left - right
                    let lap = 4 * Int(pixels[idx])
                        - Int(pixels[idx - bytesPerRow])
                        - Int(pixels[idx + bytesPerRow])
                        - Int(pixels[idx - 1])
                        - Int(pixels[idx + 1])
                    let d = Double(lap)
                    sum += d
                    sumSq += d * d
                    count += 1
                }
            }

            guard count > 0 else { return 0 }
            let mean = sum / count
            let variance = sumSq / count - mean * mean
            return CGFloat(variance)
        }

        // MARK: Barcode Detection

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            if let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
               let value = readable.stringValue {
                let barcodeBounds = readable.bounds

                // If this is a new barcode, reset best-frame tracking
                if value != collectingForBarcode {
                    collectingForBarcode = value
                    bestBarcodeCrop = nil
                    bestBarcodeSharpness = 0
                }

                // Update bounds so video frames keep evaluating
                pendingBarcodeBounds = barcodeBounds

                // Also evaluate the latest available frame immediately
                if let buffer = latestSampleBuffer {
                    evaluateFrame(buffer, bounds: barcodeBounds)
                }

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

            let isBarcodeCapture = isCapturingBarcodePhoto
            isCapturingBarcodePhoto = false

            Task { @MainActor in
                if isBarcodeCapture {
                    // Manual barcode photo → save as barcode photo and update status
                    viewModel.didCaptureBarcodePhoto(image)
                    viewModel.barcodeCaptureStatus = .captured
                } else {
                    viewModel.didCapturePhoto(image)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ScannerView()
}
