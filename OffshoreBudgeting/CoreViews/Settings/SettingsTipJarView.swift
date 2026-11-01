import SwiftUI
import StoreKit

struct SettingsTipJarView: View {
    @State private var store = TipJarStore.shared

    var body: some View {
        List {
            Section {
                Text("Offshore is free. If it helps you, you can leave an optional tip to support my work. Thank you!")
            }

            Section {
                if store.isLoading {
                    ProgressView("Loading tips…")
                } else {
                    ForEach(store.products) { product in
                        Button {
                            Task { await store.purchase(product) }
                        } label: {
                            HStack {
                                Text(product.displayName)
                                Spacer()
                                Text(product.displayPrice)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(store.isPurchasing)
                    }
                    if store.products.count < TipJarStore.productIDs.count {
                        Text("Some tips are currently unavailable. Please try again later.")
                            .foregroundStyle(.secondary)
                        Button("Retry") {
                            Task { await store.loadProducts() }
                        }
                        .disabled(store.isPurchasing)
                    }
                }
            } header: {
                Text("Leave a Tip")
            } footer: {
                Text("Every tip is a one-time purchase through Apple. Tips unlock no features, and all app features remain free. You can tip again whenever you like.")
            }
        }
        .navigationTitle("Tip Jar")
        .task { await store.loadProducts() }
        .alert("Tip Jar", isPresented: Binding(
            get: { store.message != nil },
            set: { if !$0 { store.message = nil } }
        )) {
            Button("OK") { store.message = nil }
        } message: {
            Text(store.message ?? "")
        }
    }
}
