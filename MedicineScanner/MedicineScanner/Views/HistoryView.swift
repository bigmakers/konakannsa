import SwiftUI

/// Displays scan history grouped by date, with the ability to reprint.
struct HistoryView: View {
    @State private var records: [HistoryRecord] = []
    @State private var showDeleteAllAlert = false
    @AppStorage("isMonochrome") private var isMonochrome = false

    @State private var isPrinting = false
    @State private var printError: String?

    // Search by scanID
    @State private var searchText = ""
    @State private var foundRecord: HistoryRecord?
    @State private var showPhotoDetail = false
    @State private var searchNotFound = false
    @State private var showJournalChoice = false

    var body: some View {
        VStack(spacing: 0) {
            // ScanID search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("撮影IDで検索", text: $searchText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                Button("検索") {
                    performSearch()
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(searchText.isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if records.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "clock.badge.xmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("履歴はありません")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(groupedByDate, id: \.key) { group in
                        Section(group.key) {
                            ForEach(group.records) { record in
                                HistoryRow(record: record, isMonochrome: isMonochrome)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        foundRecord = record
                                        showPhotoDetail = true
                                    }
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
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    if !records.isEmpty {
                        Button {
                            showJournalChoice = true
                        } label: {
                            Image(systemName: "doc.text")
                        }

                        Button("全削除", role: .destructive) {
                            showDeleteAllAlert = true
                        }
                        .foregroundStyle(.red)
                    }
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
        .alert("見つかりません", isPresented: $searchNotFound) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("撮影ID「\(searchText)」に一致する記録はありません。")
        }
        .confirmationDialog("ジャーナル印刷", isPresented: $showJournalChoice, titleVisibility: .visible) {
            Button("A4で印刷") { printJournal(layout: .a4) }
            Button("レシートで印刷（58mm）") { printJournal(layout: .receipt58mm) }
            Button("キャンセル", role: .cancel) {}
        }
        .sheet(isPresented: $showPhotoDetail) {
            if let record = foundRecord {
                PhotoDetailSheet(record: record, isMonochrome: isMonochrome)
            }
        }
        .onAppear { reload() }
    }

    // MARK: - Search

    private func performSearch() {
        guard let scanID = Int(searchText) else {
            searchNotFound = true
            return
        }
        if let record = HistoryStore.find(byScanID: scanID) {
            foundRecord = record
            showPhotoDetail = true
        } else {
            searchNotFound = true
        }
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

    // MARK: - Journal Print

    private func printJournal(layout: PrintHelper.PageLayout = .a4) {
        isPrinting = true

        guard let journalImage = PrintHelper.journalImage(records: records, layout: layout) else {
            printError = "ジャーナル印刷用レイアウトの生成に失敗しました。"
            isPrinting = false
            return
        }

        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo.printInfo()
        printInfo.outputType = .general
        printInfo.jobName = "秤量ジャーナル"

        printController.printInfo = printInfo
        printController.printingItem = journalImage

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
                HStack(spacing: 8) {
                    Text("#\(record.scanIDString)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.blue)
                    if !record.weight.isEmpty {
                        Text("\(record.weight)g")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.orange)
                    }
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

// MARK: - Photo Detail Sheet

struct PhotoDetailSheet: View {
    let record: HistoryRecord
    let isMonochrome: Bool
    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月d日 HH:mm"
        return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text(record.medicineName)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    HStack(spacing: 16) {
                        Label("#\(record.scanIDString)", systemImage: "number")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.blue)
                        if !record.weight.isEmpty {
                            Label("\(record.weight)g", systemImage: "scalemass.fill")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.orange)
                        }
                    }

                    Text(Self.dateFormatter.string(from: record.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let photo = record.photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .saturation(isMonochrome ? 0 : 1)
                            .contrast(isMonochrome ? 1.3 : 1)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(radius: 4)
                            .padding(.horizontal)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray5))
                            .frame(height: 200)
                            .overlay {
                                VStack {
                                    Image(systemName: "photo")
                                        .font(.largeTitle)
                                    Text("写真が見つかりません")
                                        .font(.caption)
                                }
                                .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                    }
                }
                .padding(.top, 20)
            }
            .navigationTitle("撮影ID: \(record.scanIDString)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        HistoryView()
    }
}
