import SwiftUI
import StoreKit

/// Reusable card displaying a single StoreKit product with a subscribe CTA.
struct PlanCard: View {
    let product: Product
    let badge: String?
    let isPurchasing: Bool
    let onSubscribe: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(productTitle)
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.2))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(product.displayPrice)
                    .font(.system(size: 34, weight: .bold))
                Text(cadence)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text(product.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button(action: onSubscribe) {
                HStack {
                    if isPurchasing {
                        ProgressView().controlSize(.small)
                    }
                    Text("Subscribe").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isPurchasing)
        }
        .padding(20)
        .frame(width: 240, height: 280)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 2)
        )
    }

    private var productTitle: String {
        product.displayName
    }

    private var cadence: String {
        switch product.id {
        case SubscriptionProductIDs.monthly: return "/ month"
        case SubscriptionProductIDs.yearly:  return "/ year"
        default: return ""
        }
    }
}
