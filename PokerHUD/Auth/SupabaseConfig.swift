import Foundation

/// Static configuration for the Supabase backend.
///
/// The anon (publishable) key is safe to ship in the client because all
/// security is enforced server-side via Row Level Security policies.
enum SupabaseConfig {
    static let url: URL = URL(string: "https://dyrarstybiimhchvomee.supabase.co")!
    static let anonKey: String = "sb_publishable_o2GmB3vfr0DUFBHIDQ-LQg_bdp-SNrq"

    /// Keychain service identifier used to namespace persisted auth tokens.
    static let keychainService: String = "com.pokerhud.app.supabase"
}
