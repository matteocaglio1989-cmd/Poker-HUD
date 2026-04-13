// PaywallView.swift
// PokerEye HUD
//
// A subscription paywall UI. Shows when the user tries to access Pro features.
// Add this file to your Xcode project under a "Subscription" group.

import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject var storeKit: StoreKitManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            
            // Header
            VStack(spacing: 8) {
                Image(systemName: "suit.spade.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
                
                Text("PokerEye Pro")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Unlock the full power of your HUD")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 24)
            
            // Features list
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "chart.bar.fill", text: "Advanced statistics (3-bet, C-bet, AF)")
                FeatureRow(icon: "person.2.fill", text: "Unlimited player profiles")
                FeatureRow(icon: "paintbrush.fill", text: "Customizable HUD layout")
                FeatureRow(icon: "clock.fill", text: "Full session history & analytics")
                FeatureRow(icon: "arrow.triangle.2.circlepath", text: "Automatic hand history sync")
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Subscription options
            if storeKit.isLoading {
                ProgressView("Loading...")
            } else {
                VStack(spacing: 12) {
                    ForEach(storeKit.products, id: \.id) { product in
                        SubscriptionButton(product: product) {
                            Task {
                                _ = try? await storeKit.purchase(product)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            
            // Error message
            if let error = storeKit.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            // Restore purchases
            Button("Restore Purchases") {
                Task {
                    await storeKit.restorePurchases()
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            // Legal links
            HStack(spacing: 16) {
                Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("Privacy Policy", destination: URL(string: "https://github.com/matteocaglio1989-cmd/Poker-HUD/blob/main/PRIVACY.md")!)
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.bottom, 16)
        }
        .frame(minWidth: 400, minHeight: 500)
        .onChange(of: storeKit.isSubscribed) { subscribed in
            if subscribed {
                dismiss()
            }
        }
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            Text(text)
                .font(.body)
        }
    }
}

// MARK: - Subscription Button

struct SubscriptionButton: View {
    let product: Product
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName)
                        .font(.headline)
                    Text(product.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(product.displayPrice)
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    PaywallView()
}
