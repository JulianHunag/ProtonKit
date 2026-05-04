import SwiftUI
import ProtonCore

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var username = ""
    @Published var password = ""
    @Published var twoFactorCode = ""
    @Published var showTwoFactor = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var focusPassword = false

    func login(session: SessionManager, isAddingAccount: Bool) async {
        guard !username.isEmpty, !password.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        do {
            try await session.login(username: username, password: password)
            if session.needsTwoFactor {
                showTwoFactor = true
            } else if isAddingAccount {
                session.isAddingAccount = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func submit2FA(session: SessionManager, isAddingAccount: Bool) async {
        guard twoFactorCode.count >= 6 else { return }
        isLoading = true
        errorMessage = nil

        do {
            try await session.submit2FA(code: twoFactorCode, password: password)
            if isAddingAccount {
                session.isAddingAccount = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func cancelTwoFactor(session: SessionManager) {
        showTwoFactor = false
        twoFactorCode = ""
        password = ""
        errorMessage = nil
        session.cancelTwoFactor()
    }
}
