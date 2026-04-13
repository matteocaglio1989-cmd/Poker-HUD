import Foundation
import Supabase

/// Builds and exposes a single shared `SupabaseClient` for the app.
///
/// We inject `KeychainLocalStorage` so that auth tokens persist in the macOS
/// Keychain instead of the SDK's default file-based storage.
enum SupabaseClientProvider {
    static let shared: SupabaseClient = {
        SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    storage: KeychainLocalStorage()
                )
            )
        )
    }()
}
