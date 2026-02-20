import StoreKit
import SwiftUI

/// Purchase screen for premium unlock and donations.
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
                            // Premium
                            if let premium = store.products.first(where: { $0.id == StoreManager.premiumID }) {
                                ProductButton(
                                    product: premium,
                                    label: "プレミアム（無制限）",
                                    icon: "star.fill",
                                    accent: .primary
                                ) {
                                    Task { await store.purchase(premium) }
                                }
                            }

                            Divider().padding(.vertical, 8)

                            Text("開発を応援する")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24)

                            // Donations
                            ForEach(store.products.filter { $0.id != StoreManager.premiumID }, id: \.id) { product in
                                ProductButton(
                                    product: product,
                                    label: "寄付",
                                    icon: "heart.fill",
                                    accent: .orange
                                ) {
                                    Task { await store.purchase(product) }
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
                    Text(product.displayName)
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
