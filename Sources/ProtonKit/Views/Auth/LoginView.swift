import SwiftUI
import ProtonCore

struct LoginView: View {
    @EnvironmentObject var session: SessionManager
    @StateObject private var vm = LoginViewModel()
    var isAddingAccount: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if isAddingAccount {
                HStack {
                    Spacer()
                    Button(action: { session.isAddingAccount = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                }
            }

            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.system(size: 48))
                    .foregroundStyle(.purple)

                Text(isAddingAccount ? "Add Account" : "ProtonKit")
                    .font(.largeTitle.bold())

                Text("Sign in to your Proton Mail account")
                    .foregroundStyle(.secondary)

                if vm.showTwoFactor {
                    twoFactorForm
                } else {
                    loginForm
                }

                if let error = vm.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .frame(width: 360)
            .padding(40)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var loginForm: some View {
        VStack(spacing: 16) {
            TextField("Email or username", text: $vm.username)
                .textFieldStyle(.roundedBorder)
                .textContentType(.username)
                .onSubmit { vm.focusPassword = true }

            SecureField("Password", text: $vm.password)
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)
                .onSubmit { Task { await vm.login(session: session, isAddingAccount: isAddingAccount) } }

            Button(action: { Task { await vm.login(session: session, isAddingAccount: isAddingAccount) } }) {
                if vm.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Sign In")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .controlSize(.large)
            .disabled(vm.username.isEmpty || vm.password.isEmpty || vm.isLoading)
        }
    }

    private var twoFactorForm: some View {
        VStack(spacing: 16) {
            Text("Two-factor authentication")
                .font(.headline)

            Text("Enter the 6-digit code from your authenticator app")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("000000", text: $vm.twoFactorCode)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .font(.title2.monospaced())
                .onSubmit { Task { await vm.submit2FA(session: session, isAddingAccount: isAddingAccount) } }

            Button(action: { Task { await vm.submit2FA(session: session, isAddingAccount: isAddingAccount) } }) {
                if vm.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Verify")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .controlSize(.large)
            .disabled(vm.twoFactorCode.count < 6 || vm.isLoading)

            Button("Back") {
                vm.cancelTwoFactor(session: session)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}
