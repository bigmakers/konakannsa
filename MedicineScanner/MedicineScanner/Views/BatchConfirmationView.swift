import SwiftUI

/// Displays all accumulated scanned items in a list and allows the user to
/// print them all together on a single A4 page or remove individual items.
struct BatchConfirmationView: View {
    @ObservedObject var viewModel: ScannerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isPrinting = false
    @State private var printError: String?

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
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.medicineName)
                                    .font(.body.bold())
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
                    printBatchLayout()
                } label: {
                    Label(
                        "まとめて印刷（\(viewModel.scannedItems.count)件）",
                        systemImage: "printer.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
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
    }

    // MARK: - Batch Printing

    private func printBatchLayout() {
        isPrinting = true

        guard let printableImage = PrintHelper.compositeBatchImage(
            items: viewModel.scannedItems
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
}

// MARK: - Preview

#Preview {
    NavigationStack {
        BatchConfirmationView(viewModel: {
            let vm = ScannerViewModel()
            vm.scannedItems = [
                ScannedItem(barcode: "4987123456789", medicineName: "ロキソニンS 12錠", photo: UIImage(systemName: "pill.fill")!),
                ScannedItem(barcode: "4987234567890", medicineName: "バファリンA 20錠", photo: UIImage(systemName: "pill.fill")!),
                ScannedItem(barcode: "4987345678901", medicineName: "パブロンゴールドA 44錠", photo: UIImage(systemName: "pill.fill")!),
            ]
            return vm
        }())
    }
}
