import SwiftUI

/// Maintenance screen for viewing and managing registered medicines.
/// Users can edit names and delete user-registered entries.
struct MedicineListView: View {
    @State private var entries: [MedicineService.MedicineEntry] = []
    @State private var editingEntry: MedicineService.MedicineEntry?
    @State private var editedName = ""
    @State private var showEditAlert = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("ユーザー登録") {
                let userEntries = entries.filter { !$0.isBuiltIn }
                if userEntries.isEmpty {
                    Text("ユーザー登録の医薬品はありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(userEntries) { entry in
                        MedicineRow(entry: entry) {
                            editingEntry = entry
                            editedName = entry.name
                            showEditAlert = true
                        }
                    }
                    .onDelete { indexSet in
                        let targets = indexSet.map { userEntries[$0] }
                        for target in targets {
                            MedicineService.delete(barcode: target.barcode)
                        }
                        reload()
                    }
                }
            }

            Section("組み込み") {
                ForEach(entries.filter { $0.isBuiltIn }) { entry in
                    MedicineRow(entry: entry, onTap: nil)
                }
            }
        }
        .navigationTitle("医薬品マスタ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .onAppear { reload() }
        .alert("薬品名を編集", isPresented: $showEditAlert) {
            TextField("薬品名", text: $editedName)
            Button("保存") {
                if let entry = editingEntry {
                    MedicineService.update(barcode: entry.barcode, name: editedName)
                    reload()
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("バーコード: \(editingEntry?.barcode ?? "")")
        }
    }

    private func reload() {
        entries = MedicineService.allEntries()
    }
}

// MARK: - Row

private struct MedicineRow: View {
    let entry: MedicineService.MedicineEntry
    let onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(.body.bold())
                    .foregroundStyle(.primary)
                Text(entry.barcode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        .disabled(onTap == nil)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MedicineListView()
    }
}
