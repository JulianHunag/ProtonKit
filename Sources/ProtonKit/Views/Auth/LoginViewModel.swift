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
    @Published var showCaptcha = false
    var captchaURL: URL?
    private var hvResponseToken: String?

    func login(session: SessionManager, isAddingAccount: Bool) async {
        guard !username.isEmpty, !password.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        do {
            try await session.login(
                username: username,
                password: password,
                hvToken: hvResponseToken,
                hvTokenType: hvResponseToken != nil ? "captcha" : nil
            )
            hvResponseToken = nil
            if session.needsTwoFactor {
                showTwoFactor = true
            } else if isAddingAccount {
                session.isAddingAccount = false
            }
        } catch {
            hvResponseToken = nil
            if case ProtonAPIError.humanVerificationRequired(_, _, let webUrl) = error {
                captchaURL = URL(string: webUrl)
                showCaptcha = true
            } else {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
    }

    func onCaptchaCompleted(token: String, session: SessionManager, isAddingAccount: Bool) {
        showCaptcha = false
        hvResponseToken = token
        Task {
            await login(session: session, isAddingAccount: isAddingAccount)
        }
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
