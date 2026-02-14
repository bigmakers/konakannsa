import SwiftUI

/// Displays scan history grouped by date, with the ability to reprint.
struct HistoryView: View {
    @State private var records: [HistoryRecord] = []
    @State private var showDeleteAllAlert = false
    @AppStorage("isMonochrome") private var isMonochrome = false

    @State private var isPrinting = false
    @State private var printError: String?

    var body: some View {
        Group {
            if records.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "clock.badge.xmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("履歴はありません")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(groupedByDate, id: \.key) { group in
                        Section(group.key) {
                            ForEach(group.records) { record in
                                HistoryRow(record: record, isMonochrome: isMonochrome)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            HistoryStore.delete(record)
                                            reload()
                                        } label: {
                                            Label("削除", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            reprintRecord(record)
                                        } label: {
                                            Label("再印刷", systemImage: "printer")
                                        }
                                        .tint(.orange)
                                    }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("印刷履歴")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !records.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("全削除", role: .destructive) {
                        showDeleteAllAlert = true
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .alert("全ての履歴を削除しますか？", isPresented: $showDeleteAllAlert) {
            Button("削除", role: .destructive) {
                HistoryStore.deleteAll()
                reload()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("保存された写真も全て削除されます。この操作は元に戻せません。")
        }
        .alert("印刷エラー", isPresented: .init(
            get: { printError != nil },
            set: { if !$0 { printError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(printError ?? "")
        }
        .onAppear { reload() }
    }

    // MARK: - Grouping

    private struct DateGroup {
        let key: String
        let records: [HistoryRecord]
    }

    private var groupedByDate: [DateGroup] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日（E）"

        let grouped = Dictionary(grouping: records) { record in
            formatter.string(from: record.date)
        }

        // Sort groups by the first record's date (newest first)
        return grouped
            .map { DateGroup(key: $0.key, records: $0.value.sorted { $0.date > $1.date }) }
            .sorted { ($0.records.first?.date ?? .distantPast) > ($1.records.first?.date ?? .distantPast) }
    }

    // MARK: - Helpers

    private func reload() {
        records = HistoryStore.loadAll()
    }

    private func reprintRecord(_ record: HistoryRecord) {
        guard let photo = record.photo else {
            printError = "写真の読み込みに失敗しました。"
            return
        }

        isPrinting = true

        guard let printableImage = PrintHelper.compositeImage(
            medicineName: record.medicineName,
            weight: record.weight,
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
        printInfo.jobName = "お薬 – \(record.medicineName)"

        printController.printInfo = printInfo
        printController.printingItem = printableImage

        printController.present(animated: true) { _, _, error in
            isPrinting = false
            if let error {
                printError = error.localizedDescription
            }
        }
    }
}

// MARK: - Row

private struct HistoryRow: View {
    let record: HistoryRecord
    let isMonochrome: Bool

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            if let photo = record.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .saturation(isMonochrome ? 0 : 1)
                    .contrast(isMonochrome ? 1.3 : 1)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(record.medicineName)
                    .font(.body.bold())
                if !record.weight.isEmpty {
                    Text("\(record.weight)g")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.orange)
                }
                Text(Self.timeFormatter.string(from: record.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        HistoryView()
    }
}
