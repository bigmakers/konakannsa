import SwiftUI

/// Preview screen showing the captured photo alongside the medicine name and
/// OCR-recognized weight. Provides options to print a single item, or add it
/// to the batch list for multi-medicine printing.
struct ConfirmationView: View {
    let photo: UIImage
    let medicineName: String

    /// Binding to the OCR-recognized weight value (editable).
    @Binding var weight: String

    /// Whether OCR is currently in progress.
    var isRecognizingWeight: Bool = false

    /// Whether monochrome (B&W high-contrast) mode is active.
    var isMonochrome: Bool = false

    /// Number of items already in the batch list (shown in badge).
    var batchCount: Int = 0

    /// Called when the user taps "リストに追加して次へ".
    var onAddToList: (() -> Void)?

    /// Called after the user finishes (or cancels) the print flow so
    /// the parent can reset the scanner.
    var onDone: () -> Void

    @State private var isPrinting = false
    @State private var printError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text(medicineName)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Weight display / edit
            HStack(spacing: 8) {
                Image(systemName: "scalemass.fill")
                    .foregroundStyle(.secondary)
                if isRecognizingWeight {
                    ProgressView()
                        .controlSize(.small)
                    Text("読み取り中...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    TextField("秤の数値", text: $weight)
                        .font(.title3.monospacedDigit())
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                        .frame(maxWidth: 160)
                    Text("g")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            Image(uiImage: photo)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 280)
                .saturation(isMonochrome ? 0 : 1)
                .contrast(isMonochrome ? 1.3 : 1)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 4)
                .padding(.horizontal)

            Spacer()

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
                .padding(.horizontal, 40)
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
            .padding(.horizontal, 40)
            .disabled(isPrinting)

            Button("スキャナーに戻る") {
                dismiss()
                onDone()
            }
            .font(.subheadline)
            .padding(.bottom, 8)
        }
        .padding(.top, 20)
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

    // MARK: - Printing

    private func printCombinedLayout() {
        isPrinting = true

        guard let printableImage = PrintHelper.compositeImage(
            medicineName: medicineName,
            weight: weight,
            photo: photo,
            layout: .a4,
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
            onAddToList: {}
        ) {}
    }
}
