import SwiftUI

/// Maintenance screen for viewing and managing registered medicines.
/// Users can edit names and delete user-registered entries.
struct MedicineListView: View {
    @ObservedObject var store: StoreManager
    @State private var entries: [MedicineService.MedicineEntry] = []
    @State private var editingEntry: MedicineService.MedicineEntry?
    @State private var editedName = ""
    @State private var showEditAlert = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            if entries.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "pills")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("登録された医薬品はありません")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("スキャン時に未登録バーコードを検出すると\n登録画面が表示されます")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            } else {
                List {
                    // Registration count
                    if !store.isPremium {
                        Section {
                            HStack {
                                Text("登録数")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(entries.count) / \(StoreManager.freeLimit)")
                                    .font(.subheadline.bold().monospacedDigit())
                                    .foregroundStyle(entries.count >= StoreManager.freeLimit ? .red : .secondary)
                            }
                            if entries.count >= StoreManager.freeLimit {
                                Button("プレミアムにアップグレード（無制限）") {
                                    store.showPaywall = true
                                }
                                .font(.subheadline)
                            }
                        }
                    }

                    Section("登録済み医薬品") {
                        ForEach(entries) { entry in
                            MedicineRow(entry: entry) {
                                editingEntry = entry
                                editedName = entry.name
                                showEditAlert = true
                            }
                        }
                        .onDelete { indexSet in
                            let targets = indexSet.map { entries[$0] }
                            for target in targets {
                                MedicineService.delete(barcode: target.barcode)
                            }
                            reload()
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }

            // Bottom: back to scanner button
            VStack(spacing: 8) {
                Divider()
                Button {
                    dismiss()
                } label: {
                    Label("スキャナーに戻る", systemImage: "barcode.viewfinder")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
        .navigationTitle("医薬品マスタ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !entries.isEmpty {
                    EditButton()
                }
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
        entries = MedicineService.userEntries()
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
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name)
                        .font(.body.bold())
                        .foregroundStyle(.primary)
                    Text(entry.barcode)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "pencil.circle")
                    .font(.title3)
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
        MedicineListView(store: StoreManager.shared)
    }
}
