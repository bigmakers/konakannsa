import SwiftUI

/// Preview screen showing the captured photo alongside the medicine name.
/// Provides options to print a single item, or add it to the batch list
/// for multi-medicine printing.
struct ConfirmationView: View {
    let photo: UIImage
    let medicineName: String

    /// Binding to the weight value (manual input).
    @Binding var weight: String

    /// Whether monochrome (B&W high-contrast) mode is active.
    var isMonochrome: Bool = false

    /// Number of items already in the batch list (shown in badge).
    var batchCount: Int = 0

    /// Called when the user taps "リストに追加して次へ".
    var onAddToList: (() -> Void)?

    /// Called when the user taps "再撮影".
    var onRetake: (() -> Void)?

    /// Called after the user finishes (or cancels) the print flow so
    /// the parent can reset the scanner.
    var onDone: () -> Void

    @State private var isPrinting = false
    @State private var printError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(medicineName)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Photo (left) + Numpad (right) side by side
                HStack(alignment: .top, spacing: 12) {
                    // Photo + retake button
                    ZStack(alignment: .bottomTrailing) {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .saturation(isMonochrome ? 0 : 1)
                            .contrast(isMonochrome ? 1.3 : 1)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(radius: 4)

                        Button {
                            if let onRetake {
                                dismiss()
                                onRetake()
                            }
                        } label: {
                            Label("再撮影", systemImage: "camera.fill")
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .padding(6)
                    }
                    .frame(maxWidth: .infinity)

                    // Weight display + numpad
                    VStack(spacing: 8) {
                        // Weight display
                        HStack(spacing: 4) {
                            Image(systemName: "scalemass.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text(weight.isEmpty ? "0" : weight)
                                .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(weight.isEmpty ? .secondary : .primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text("g")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }

                        // Numpad grid (4 rows x 3 columns)
                        let keys = [
                            ["7","8","9"],
                            ["4","5","6"],
                            ["1","2","3"],
                            [".","0","⌫"],
                        ]
                        VStack(spacing: 4) {
                            ForEach(keys, id: \.self) { row in
                                HStack(spacing: 4) {
                                    ForEach(row, id: \.self) { key in
                                        Button {
                                            if key == "⌫" {
                                                if !weight.isEmpty { weight.removeLast() }
                                            } else {
                                                tapKey(key)
                                            }
                                        } label: {
                                            Text(key)
                                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 44)
                                                .background(
                                                    key == "⌫"
                                                        ? Color(.systemGray4)
                                                        : Color(.systemGray5),
                                                    in: RoundedRectangle(cornerRadius: 8)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        // Clear button
                        Button {
                            weight = ""
                        } label: {
                            Text("クリア")
                                .font(.caption.bold())
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(width: 160)
                }
                .padding(.horizontal)

                Spacer().frame(height: 8)

                // Add to batch list button
                if let onAddToList {
                    Button {
                        dismiss()
                        onAddToList()
                    } label: {
                        Label(
                            batchCount > 0
                                ? "リストに追加して次へ（\(batchCount)件登録済み）"
                                : "リストに追加して次へ",
                            systemImage: "plus.rectangle.on.rectangle"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isMonochrome ? Color.black : Color.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 24)
                }

                // Single-item print button
                Button {
                    printCombinedLayout()
                } label: {
                    Label("この1件を印刷", systemImage: "printer.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isMonochrome ? Color.black : Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .disabled(isPrinting)

                // Back to scanner (large)
                Button {
                    dismiss()
                    onDone()
                } label: {
                    Label("追加せずにスキャナーに戻る", systemImage: "arrow.uturn.backward")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray4))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .padding(.top, 20)
        }
        .navigationTitle("確認")
        .navigationBarTitleDisplayMode(.inline)
        .alert("印刷エラー", isPresented: .init(
            get: { printError != nil },
            set: { if !$0 { printError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(printError ?? "")
        }
    }

    // MARK: - Number Input

    private func tapKey(_ key: String) {
        if key == "." {
            if weight.contains(".") { return }
            if weight.isEmpty { weight = "0" }
        }
        weight.append(key)
    }

    // MARK: - Printing

    private func printCombinedLayout() {
        isPrinting = true

        // Save first to get scanID
        let scanID = HistoryStore.save(
            barcode: "",
            medicineName: medicineName,
            weight: weight,
            photo: photo
        )

        var item = ScannedItem(
            barcode: "",
            medicineName: medicineName,
            weight: weight,
            photo: photo
        )
        item.scanID = scanID

        guard let printableImage = PrintHelper.compositeBatchImage(
            items: [item],
            monochrome: isMonochrome
        ) else {
            printError = "印刷用レイアウトの生成に失敗しました。"
            isPrinting = false
            return
        }

        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo.printInfo()
        printInfo.outputType = .general
        printInfo.jobName = "お薬 – \(medicineName)"

        printController.printInfo = printInfo
        printController.printingItem = printableImage

        printController.present(animated: true) { _, completed, error in
            isPrinting = false
            if let error {
                printError = error.localizedDescription
            } else if completed {
                dismiss()
                onDone()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ConfirmationView(
            photo: UIImage(systemName: "pill.fill")!,
            medicineName: "ロキソニンS 12錠",
            weight: .constant("12.5"),
            batchCount: 2,
            onAddToList: {},
            onRetake: {}
        ) {}
    }
}
