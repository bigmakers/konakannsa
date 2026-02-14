import SwiftUI

/// Displays all accumulated scanned items in a list and allows the user to
/// print them all together on a single A4 page or remove individual items.
struct BatchConfirmationView: View {
    @ObservedObject var viewModel: ScannerViewModel
    @AppStorage("isMonochrome") private var isMonochrome = false
    @Environment(\.dismiss) private var dismiss

    @State private var isPrinting = false
    @State private var printError: String?
    @State private var showPrintChoice = false

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.scannedItems.isEmpty {
                Spacer()
                Text("リストにお薬がありません")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(viewModel.scannedItems) { item in
                        HStack(spacing: 12) {
                            Image(uiImage: item.photo)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 60)
                                .saturation(isMonochrome ? 0 : 1)
                                .contrast(isMonochrome ? 1.3 : 1)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.medicineName)
                                    .font(.body.bold())
                                if !item.weight.isEmpty {
                                    Text("\(item.weight)g")
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(.orange)
                                }
                                Text(item.barcode)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { indexSet in
                        viewModel.scannedItems.remove(atOffsets: indexSet)
                    }
                }
                .listStyle(.plain)
            }

            // Bottom action area
            VStack(spacing: 12) {
                Divider()

                Button {
                    showPrintChoice = true
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
                .disabled(isPrinting || viewModel.scannedItems.isEmpty)

                HStack(spacing: 20) {
                    Button("スキャナーに戻る") {
                        dismiss()
                    }
                    .font(.subheadline)

                    if !viewModel.scannedItems.isEmpty {
                        Button("リストをクリア") {
                            viewModel.resetAll()
                            dismiss()
                        }
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    }
                }
                .padding(.bottom, 8)
            }
            .padding(.top, 8)
        }
        .navigationTitle("お薬リスト")
        .navigationBarTitleDisplayMode(.inline)
        .alert("印刷エラー", isPresented: .init(
            get: { printError != nil },
            set: { if !$0 { printError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(printError ?? "")
        }
        .confirmationDialog(
            "印刷形式を選択",
            isPresented: $showPrintChoice,
            titleVisibility: .visible
        ) {
            Button("写真付き印刷") {
                printBatchWithPhotos()
            }
            Button("ジャーナル印刷（リスト）") {
                printBatchJournal()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("写真付き: 写真・薬品名・秤量を一覧印刷\nジャーナル: 日付・撮影ID・薬品名・秤量のリスト印刷")
        }
    }

    // MARK: - Batch Printing (Photos)

    private func printBatchWithPhotos() {
        isPrinting = true

        // Save to history first to get scanIDs
        let scanIDs = HistoryStore.saveBatch(viewModel.scannedItems)

        // Attach scanIDs to items for rendering
        var itemsWithIDs = viewModel.scannedItems
        for i in itemsWithIDs.indices {
            if i < scanIDs.count {
                itemsWithIDs[i].scanID = scanIDs[i]
            }
        }

        guard let printableImage = PrintHelper.compositeBatchImage(
            items: itemsWithIDs,
            monochrome: isMonochrome
        ) else {
            printError = "印刷用レイアウトの生成に失敗しました。"
            isPrinting = false
            return
        }

        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo.printInfo()
        printInfo.outputType = .general
        printInfo.jobName = "お薬一覧（\(viewModel.scannedItems.count)件）"

        printController.printInfo = printInfo
        printController.printingItem = printableImage

        printController.present(animated: true) { _, completed, error in
            isPrinting = false
            if let error {
                printError = error.localizedDescription
            } else if completed {
                viewModel.resetAll()
                dismiss()
            }
        }
    }

    // MARK: - Batch Printing (Journal)

    private func printBatchJournal() {
        isPrinting = true

        // Save to history first so each item gets a scanID
        HistoryStore.saveBatch(viewModel.scannedItems)

        // Load recent records to get the scanIDs just assigned
        let allRecords = HistoryStore.loadAll()
        // Match by taking the most recent N records (just saved)
        let recentRecords = Array(allRecords.prefix(viewModel.scannedItems.count))

        guard let journalImage = PrintHelper.journalImage(records: recentRecords) else {
            printError = "ジャーナル印刷用レイアウトの生成に失敗しました。"
            isPrinting = false
            return
        }

        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo.printInfo()
        printInfo.outputType = .general
        printInfo.jobName = "秤量ジャーナル（\(viewModel.scannedItems.count)件）"

        printController.printInfo = printInfo
        printController.printingItem = journalImage

        printController.present(animated: true) { _, completed, error in
            isPrinting = false
            if let error {
                printError = error.localizedDescription
            } else if completed {
                viewModel.resetAll()
                dismiss()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        BatchConfirmationView(viewModel: {
            let vm = ScannerViewModel()
            vm.scannedItems = [
                ScannedItem(barcode: "4987123456789", medicineName: "ロキソニンS 12錠", weight: "12.5", photo: UIImage(systemName: "pill.fill")!),
                ScannedItem(barcode: "4987234567890", medicineName: "バファリンA 20錠", weight: "8.3", photo: UIImage(systemName: "pill.fill")!),
                ScannedItem(barcode: "4987345678901", medicineName: "パブロンゴールドA 44錠", weight: "", photo: UIImage(systemName: "pill.fill")!),
            ]
            return vm
        }())
    }
}
