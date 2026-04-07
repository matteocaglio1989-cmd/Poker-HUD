import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var email: String
    let onSwitchToSignUp: () -> Void
    let onSwitchToForgotPassword: () -> Void

    @State private var password: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sign In")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 6) {
                Text("Email").font(.caption).foregroundStyle(.secondary)
                TextField("you@example.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Password").font(.caption).foregroundStyle(.secondary)
                SecureField("••••••••", text: $password)
                    .textFieldStyle(.roundedBorder)
            }

            if let error = appState.authService.authError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task { await appState.authService.signIn(email: email, password: password) }
            } label: {
                HStack {
                    if appState.authService.isLoading {
                        ProgressView().controlSize(.small)
                    }
                    Text("Sign In").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isFormValid || appState.authService.isLoading)

            HStack {
                Button("Forgot password?", action: onSwitchToForgotPassword)
                    .buttonStyle(.link)
                Spacer()
                Button("Create account", action: onSwitchToSignUp)
                    .buttonStyle(.link)
            }
            .font(.caption)
        }
    }

    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }
}
