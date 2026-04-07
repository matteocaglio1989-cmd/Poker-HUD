import SwiftUI

struct ForgotPasswordView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var email: String
    let onBackToLogin: () -> Void

    @State private var didSend: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reset Password")
                .font(.title2)
                .fontWeight(.semibold)

            if didSend {
                successView
            } else {
                formView
            }
        }
    }

    private var formView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enter your email and we'll send you a link to reset your password.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Email").font(.caption).foregroundStyle(.secondary)
                TextField("you@example.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
            }

            if let error = appState.authService.authError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task {
                    if await appState.authService.sendPasswordReset(email: email) {
                        didSend = true
                    }
                }
            } label: {
                HStack {
                    if appState.authService.isLoading {
                        ProgressView().controlSize(.small)
                    }
                    Text("Send reset link").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || appState.authService.isLoading)

            HStack {
                Spacer()
                Button("Back to sign in", action: onBackToLogin)
                    .buttonStyle(.link)
            }
            .font(.caption)
        }
    }

    private var successView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Email sent")
                    .font(.headline)
            }
            Text("If an account exists for \(email), a password reset link has been sent. Follow the link to choose a new password, then return here to sign in.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Back to sign in") {
                onBackToLogin()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
    }
}
