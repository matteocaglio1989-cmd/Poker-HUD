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
                    storage: KeychainLocalStorage(),
                    // Opt in to the new behaviour from supabase-swift PR #822:
                    // emit the locally stored session as the initial event
                    // even if its access token is expired (the SDK then
                    // refreshes it). Silences the runtime warning the SDK
                    // prints today and matches the next major release default.
                    // We don't subscribe to onAuthStateChange anywhere, so no
                    // additional `session.isExpired` check is required —
                    // `AuthService.restoreSession()` reads `client.auth.session`
                    // which already auto-refreshes.
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }()
}
