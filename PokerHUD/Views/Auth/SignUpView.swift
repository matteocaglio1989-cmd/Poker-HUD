import SwiftUI

struct SignUpView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var email: String
    let onBackToLogin: () -> Void

    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var didSubmit: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Account")
                .font(.title2)
                .fontWeight(.semibold)

            if didSubmit {
                successView
            } else {
                formView
            }
        }
    }

    private var formView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Email").font(.caption).foregroundStyle(.secondary)
                TextField("you@example.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Password").font(.caption).foregroundStyle(.secondary)
                SecureField("At least 6 characters", text: $password)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Confirm password").font(.caption).foregroundStyle(.secondary)
                SecureField("Re-enter password", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
            }

            if let validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let error = appState.authService.authError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task {
                    let outcome = await appState.authService.signUp(email: email, password: password)
                    if outcome == .confirmationRequired || outcome == .signedIn {
                        didSubmit = true
                    }
                }
            } label: {
                HStack {
                    if appState.authService.isLoading {
                        ProgressView().controlSize(.small)
                    }
                    Text("Sign Up").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isFormValid || appState.authService.isLoading)

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
                Image(systemName: "envelope.badge.fill")
                    .foregroundStyle(.green)
                Text("Check your inbox")
                    .font(.headline)
            }
            Text("We sent a confirmation link to \(email). Click the link to verify your account, then return here to sign in.")
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

    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        password.count >= 6 &&
        password == confirmPassword
    }

    private var validationError: String? {
        guard !password.isEmpty || !confirmPassword.isEmpty else { return nil }
        if password.count < 6 { return "Password must be at least 6 characters." }
        if password != confirmPassword { return "Passwords do not match." }
        return nil
    }
}
