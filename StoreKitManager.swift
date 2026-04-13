// StoreKitManager.swift
// PokerEye HUD
//
// Handles StoreKit 2 subscription purchases and syncs status to Supabase.
// Add this file to your Xcode project under a "Subscription" group.

import StoreKit
import Foundation
import Supabase

// MARK: - Product IDs (must match App Store Connect)
enum SubscriptionProduct: String, CaseIterable {
    case monthly = "com.pokereye.pokerhud.pro.monthly"
    case yearly  = "com.pokereye.pokerhud.pro.yearly"
    
    var plan: String {
        switch self {
        case .monthly: return "monthly"
        case .yearly:  return "yearly"
        }
    }
}

// MARK: - Subscription Status
enum SubscriptionStatus: Equatable {
    case subscribed
    case inTrial
    case expired
    case revoked
    case notSubscribed
}

// MARK: - StoreKit Manager
@MainActor
class StoreKitManager: ObservableObject {
    
    // Published properties for UI binding
    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    @Published var subscriptionStatus: SubscriptionStatus = .notSubscribed
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Supabase client — update with your project URL and anon key
    private let supabase: SupabaseClient
    
    // Transaction listener task
    private var transactionListener: Task<Void, Never>?
    
    init(supabaseClient: SupabaseClient) {
        self.supabase = supabaseClient
        
        // Start listening for transactions (renewals, refunds, etc.)
        transactionListener = listenForTransactions()
        
        // Load products and check current entitlements
        Task {
            await loadProducts()
            await checkCurrentEntitlements()
        }
    }
    
    deinit {
        transactionListener?.cancel()
    }
    
    // MARK: - Load Products from App Store
    
    func loadProducts() async {
        do {
            let productIDs = SubscriptionProduct.allCases.map { $0.rawValue }
            products = try await Product.products(for: productIDs)
                .sorted { $0.price < $1.price }
        } catch {
            print("❌ Failed to load products: \(error)")
            errorMessage = "Failed to load subscription options."
        }
    }
    
    // MARK: - Purchase
    
    func purchase(_ product: Product) async throws -> Bool {
        isLoading = true
        defer { isLoading = false }
        
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            
            // Sync to Supabase
            await syncSubscriptionToSupabase(transaction: transaction, product: product)
            
            // Finish the transaction
            await transaction.finish()
            
            // Update local state
            await checkCurrentEntitlements()
            return true
            
        case .userCancelled:
            return false
            
        case .pending:
            // Transaction needs approval (e.g., Ask to Buy)
            return false
            
        @unknown default:
            return false
        }
    }
    
    // MARK: - Restore Purchases
    
    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        
        try? await AppStore.sync()
        await checkCurrentEntitlements()
    }
    
    // MARK: - Check Current Entitlements
    
    func checkCurrentEntitlements() async {
        var foundActive = false
        
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            
            if SubscriptionProduct.allCases.map({ $0.rawValue }).contains(transaction.productID) {
                purchasedProductIDs.insert(transaction.productID)
                foundActive = true
                
                // Sync latest status to Supabase
                if let product = products.first(where: { $0.id == transaction.productID }) {
                    await syncSubscriptionToSupabase(transaction: transaction, product: product)
                }
            }
        }
        
        subscriptionStatus = foundActive ? .subscribed : .notSubscribed
    }
    
    // MARK: - Transaction Listener (handles renewals, refunds, revocations)
    
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                guard let transaction = try? self.checkVerified(result) else { continue }
                
                await MainActor.run {
                    Task {
                        if let product = self.products.first(where: { $0.id == transaction.productID }) {
                            await self.syncSubscriptionToSupabase(transaction: transaction, product: product)
                        }
                        await self.checkCurrentEntitlements()
                        await transaction.finish()
                    }
                }
            }
        }
    }
    
    // MARK: - Verify Transaction
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
    
    // MARK: - Sync Subscription to Supabase
    
    private func syncSubscriptionToSupabase(transaction: Transaction, product: Product) async {
        guard let userId = try? await supabase.auth.session.user.id else {
            print("❌ No authenticated user — cannot sync subscription")
            return
        }
        
        // Determine the plan from product ID
        let plan = SubscriptionProduct(rawValue: transaction.productID)?.plan ?? "monthly"
        
        // Determine subscription status
        let status: String
        if transaction.revocationDate != nil {
            status = "revoked"
        } else if let expirationDate = transaction.expirationDate, expirationDate < Date() {
            if let gracePeriod = transaction.gracePeriodExpirationDate, gracePeriod > Date() {
                status = "in_grace"
            } else {
                status = "expired"
            }
        } else {
            status = "active"
        }
        
        // Determine environment
        let environment: String
        #if DEBUG
        let env = "sandbox"
        #else
        let env = transaction.environment == .sandbox ? "sandbox" : "production"
        #endif
        _ = env // suppress unused warning
        
        // Build the subscription record
        let subscriptionData: [String: AnyJSON] = [
            "user_id": .string(userId.uuidString),
            "product_id": .string(transaction.productID),
            "plan": .string(plan),
            "status": .string(status),
            "original_transaction_id": .string(String(transaction.originalID)),
            "latest_transaction_id": .string(String(transaction.id)),
            "current_period_start": .string(
                ISO8601DateFormatter().string(from: transaction.purchaseDate)
            ),
            "current_period_end": .string(
                ISO8601DateFormatter().string(from: transaction.expirationDate ?? transaction.purchaseDate)
            ),
            "auto_renew": .bool(transaction.revocationDate == nil),
            "environment": .string(env),
            "updated_at": .string(ISO8601DateFormatter().string(from: Date()))
        ]
        
        do {
            // Upsert: insert if new, update if exists
            try await supabase
                .from("subscriptions")
                .upsert(subscriptionData, onConflict: "user_id")
                .execute()
            
            print("✅ Subscription synced to Supabase: \(status) (\(plan))")
        } catch {
            print("❌ Failed to sync subscription: \(error)")
        }
    }
    
    // MARK: - Convenience: Is User Subscribed?
    
    var isSubscribed: Bool {
        subscriptionStatus == .subscribed
    }
}
