import Foundation
import Supabase
import Auth

/// Wraps Supabase auth and exposes a SwiftUI-friendly observable surface.
///
/// All published mutations happen on the main actor so views can bind directly.
@MainActor
final class AuthService: ObservableObject {
    // Disambiguate from `PokerHUD/Models/Session.swift` (a poker hand-history
    // session). Without the `Auth.` prefix Swift resolves `Session` to the
    // GRDB model in this module, not Supabase's auth Session.
    @Published private(set) var session: Auth.Session?
    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published var authError: String?

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseClientProvider.shared) {
        self.client = client
    }

    /// Currently signed-in user's email, if any.
    var currentEmail: String? {
        session?.user.email
    }

    // MARK: - Session restore

    /// Attempts to restore a previously persisted session from the Keychain.
    /// Called once at app launch.
    func restoreSession() async {
        do {
            let restored = try await client.auth.session
            self.session = restored
            self.isAuthenticated = true
        } catch {
            // No valid persisted session — user must sign in.
            self.session = nil
            self.isAuthenticated = false
        }
    }

    // MARK: - Sign in / sign up / sign out

    func signIn(email: String, password: String) async {
        authError = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let session = try await client.auth.signIn(email: email, password: password)
            self.session = session
            self.isAuthenticated = true
        } catch {
            self.authError = friendlyMessage(for: error)
        }
    }

    /// Sign up a new user. Supabase will send a confirmation email if the
    /// project has "Confirm email" enabled, and the returned session will be
    /// `nil` until the user clicks the confirmation link.
    func signUp(email: String, password: String) async -> SignUpOutcome {
        authError = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await client.auth.signUp(email: email, password: password)
            if let session = response.session {
                // Confirmation disabled — user is signed in immediately.
                self.session = session
                self.isAuthenticated = true
                return .signedIn
            } else {
                // Confirmation required.
                return .confirmationRequired
            }
        } catch {
            self.authError = friendlyMessage(for: error)
            return .failed
        }
    }

    func sendPasswordReset(email: String) async -> Bool {
        authError = nil
        isLoading = true
        defer { isLoading = false }

        do {
            try await client.auth.resetPasswordForEmail(email)
            return true
        } catch {
            self.authError = friendlyMessage(for: error)
            return false
        }
    }

    func signOut() async {
        authError = nil
        do {
            try await client.auth.signOut()
        } catch {
            self.authError = friendlyMessage(for: error)
        }
        self.session = nil
        self.isAuthenticated = false
    }

    // MARK: - Internal

    private func friendlyMessage(for error: Error) -> String {
        let raw = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return raw.isEmpty ? "Something went wrong. Please try again." : raw
    }
}

enum SignUpOutcome {
    case signedIn
    case confirmationRequired
    case failed
}
