// INTEGRATION_GUIDE.swift
// PokerEye HUD
//
// This file shows HOW to integrate StoreKitManager into your existing app.
// Don't add this file to Xcode — use it as a reference.

// ============================================================
// STEP 1: Initialize StoreKitManager in your App entry point
// ============================================================

/*
 In your main App struct (e.g., PokerHUDApp.swift), create the
 StoreKitManager and inject it as an environment object:
 
 @main
 struct PokerHUDApp: App {
     
     // Your existing Supabase client
     let supabase = SupabaseClient(
         supabaseURL: URL(string: "https://dyrarstybiimhchvomee.supabase.co")!,
         supabaseKey: "YOUR_ANON_KEY"
     )
     
     // Create the StoreKit manager
     @StateObject private var storeKitManager: StoreKitManager
     
     init() {
         let client = SupabaseClient(
             supabaseURL: URL(string: "https://dyrarstybiimhchvomee.supabase.co")!,
             supabaseKey: "YOUR_ANON_KEY"
         )
         _storeKitManager = StateObject(wrappedValue: StoreKitManager(supabaseClient: client))
     }
     
     var body: some Scene {
         WindowGroup {
             ContentView()
                 .environmentObject(storeKitManager)
         }
     }
 }
*/


// ============================================================
// STEP 2: Gate Pro features behind subscription check
// ============================================================

/*
 In any view where you want to show Pro features or the paywall:
 
 struct HUDView: View {
     @EnvironmentObject var storeKit: StoreKitManager
     @State private var showPaywall = false
     
     var body: some View {
         VStack {
             // Free features always visible
             BasicStatsView()
             
             // Pro features gated
             if storeKit.isSubscribed {
                 AdvancedStatsView()
             } else {
                 Button("Unlock Pro Features") {
                     showPaywall = true
                 }
             }
         }
         .sheet(isPresented: $showPaywall) {
             PaywallView()
                 .environmentObject(storeKit)
         }
     }
 }
*/


// ============================================================
// STEP 3: Check subscription on app launch (from Supabase)
// ============================================================

/*
 If you want to also verify subscription status from your database
 (e.g., for server-side feature gating), you can add this method
 to StoreKitManager:
 
 func checkSubscriptionFromDatabase() async -> Bool {
     guard let userId = try? await supabase.auth.session.user.id else {
         return false
     }
     
     struct SubscriptionRow: Decodable {
         let status: String
         let current_period_end: String
     }
     
     do {
         let response: [SubscriptionRow] = try await supabase
             .from("subscriptions")
             .select("status, current_period_end")
             .eq("user_id", value: userId.uuidString)
             .eq("status", value: "active")
             .execute()
             .value
         
         return !response.isEmpty
     } catch {
         print("❌ Failed to check subscription from DB: \(error)")
         return false
     }
 }
*/


// ============================================================
// STEP 4: Add StoreKit configuration file for testing
// ============================================================

/*
 To test subscriptions in Xcode without a real App Store:
 
 1. File → New → File → StoreKit Configuration File
 2. Name it "PokerEyeProducts.storekit"
 3. Click "+" and add two subscriptions:
 
    Product ID: com.pokereye.pokerhud.pro.monthly
    Reference Name: PokerEye Pro Monthly
    Price: 4.99
    Duration: 1 Month
    
    Product ID: com.pokereye.pokerhud.pro.yearly
    Reference Name: PokerEye Pro Yearly
    Price: 39.99
    Duration: 1 Year
 
 4. In your scheme (Product → Scheme → Edit Scheme):
    - Select "Run" on the left
    - Under "Options" tab, set StoreKit Configuration to your .storekit file
 
 This lets you test purchases in the Simulator without real money.
*/


// ============================================================
// STEP 5: Supabase RLS Policies (already in place, verify these)
// ============================================================

/*
 Make sure your Supabase subscriptions table has these RLS policies:
 
 -- Users can read their own subscription
 CREATE POLICY "Users can read own subscription"
 ON subscriptions FOR SELECT
 USING (auth.uid() = user_id);
 
 -- Users can insert their own subscription
 CREATE POLICY "Users can insert own subscription"
 ON subscriptions FOR INSERT
 WITH CHECK (auth.uid() = user_id);
 
 -- Users can update their own subscription
 CREATE POLICY "Users can update own subscription"
 ON subscriptions FOR UPDATE
 USING (auth.uid() = user_id);
*/
