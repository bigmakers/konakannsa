import StoreKit
import SwiftUI

/// Purchase screen for premium unlock (one-time or yearly subscription).
struct PaywallView: View {
    @ObservedObject var store: StoreManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 48, weight: .thin))
                        .foregroundStyle(.primary)
                    Text("プレミアム")
                        .font(.title.bold())
                    Text("6品目以上の医薬品を登録するには\nプレミアムプランが必要です")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    // Current count
                    let count = MedicineService.userEntries().count
                    Text("現在の登録数: \(count) / \(StoreManager.freeLimit)")
                        .font(.caption.bold().monospacedDigit())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 4))
                }
                .padding(.top, 32)
                .padding(.bottom, 24)

                Divider()

                // Products
                ScrollView {
                    VStack(spacing: 12) {
                        if store.isLoadingProducts {
                            ProgressView("商品情報を読み込み中...")
                                .padding(.vertical, 40)
                        } else if store.products.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("商品情報を取得できませんでした")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Button("再読み込み") {
                                    Task { await store.loadProducts() }
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.vertical, 40)
                        } else {
                            // Yearly subscription
                            if let yearly = store.products.first(where: { $0.id == StoreManager.yearlyID }) {
                                ProductButton(
                                    product: yearly,
                                    label: "プレミアム年額プラン",
                                    sublabel: "自動更新・いつでも解約可能",
                                    icon: "arrow.clockwise.circle.fill",
                                    accent: .orange
                                ) {
                                    Task { await store.purchase(yearly) }
                                }
                            }
                        }

                        // Restore
                        Button("購入を復元") {
                            Task { await store.restore() }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 16)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("アップグレード")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .alert("エラー", isPresented: .init(
                get: { store.purchaseError != nil },
                set: { if !$0 { store.purchaseError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.purchaseError ?? "")
            }
        }
        .presentationDetents([.medium, .large])
        .task { await store.loadProducts() }
    }
}

// MARK: - Product Button

private struct ProductButton: View {
    let product: Product
    let label: String
    let sublabel: String
    let icon: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(accent)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.subheadline.bold())
                    Text(sublabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(product.displayPrice)
                    .font(.headline.monospacedDigit())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
    }
}
