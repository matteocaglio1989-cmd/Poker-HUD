import SwiftUI

enum AuthMode {
    case login
    case signUp
    case forgotPassword
}

/// Root authentication screen shown when no user is signed in.
/// Hosts a small state machine that swaps between login, sign-up, and
/// forgot-password subviews while preserving the entered email.
struct AuthContainerView: View {
    @EnvironmentObject private var appState: AppState
    @State private var mode: AuthMode = .login
    @State private var email: String = ""

    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                header

                AuthFormCard {
                    switch mode {
                    case .login:
                        LoginView(
                            email: $email,
                            onSwitchToSignUp: { mode = .signUp },
                            onSwitchToForgotPassword: { mode = .forgotPassword }
                        )
                    case .signUp:
                        SignUpView(
                            email: $email,
                            onBackToLogin: { mode = .login }
                        )
                    case .forgotPassword:
                        ForgotPasswordView(
                            email: $email,
                            onBackToLogin: { mode = .login }
                        )
                    }
                }
                .frame(width: 420)

                Spacer(minLength: 0)
            }
            .padding(.top, 60)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "suit.spade.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Poker HUD")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Sign in to continue")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// Shared card chrome used by all three auth subviews.
struct AuthFormCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content()
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
    }
}
